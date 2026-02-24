// bats_bridge.mjs — Bridge between bats WASM and a DOM document
// Parses the bats binary diff protocol and applies it to a standard DOM.
// Works in any ES module environment (browser or Node.js).

// Parse a little-endian i32 from a Uint8Array at offset
function readI32(buf, off) {
  return buf[off] | (buf[off+1] << 8) | (buf[off+2] << 16) | (buf[off+3] << 24);
}

/**
 * Load a bats WASM module and connect it to a DOM document.
 *
 * @param {BufferSource} wasmBytes — compiled WASM bytes
 * @param {Element} root — root element for bats to render into (node_id 0)
 * @returns {{ exports, nodes, done }} — WASM exports, node registry,
 *   and a promise that resolves when WASM calls bats_exit
 */
export async function loadWASM(wasmBytes, root, opts) {
  const extraImports = (opts && opts.extraImports) || {};
  const document = root.ownerDocument;
  let instance = null;
  let resolveDone;
  const done = new Promise(r => { resolveDone = r; });

  // Node registry: node_id -> DOM element
  const nodes = new Map();
  nodes.set(0, root);

  function readBytes(ptr, len) {
    return new Uint8Array(instance.exports.memory.buffer, ptr, len).slice();
  }

  function readString(ptr, len) {
    return new TextDecoder().decode(readBytes(ptr, len));
  }

  // JS-side data stash — WASM pulls data via bats_js_stash_read
  const dataStash = new Map();
  let nextStashId = 0;

  function stashData(data) {
    const id = nextStashId++;
    dataStash.set(id, data);
    return id;
  }

  function batsJsStashRead(stashId, destPtr, len) {
    const data = dataStash.get(stashId);
    if (data) {
      const copyLen = Math.min(len, data.length);
      new Uint8Array(instance.exports.memory.buffer).set(
        data.subarray(0, copyLen), destPtr);
      dataStash.delete(stashId);
    }
  }

  // Blob URL lifecycle tracking — revoked when element gets new image or is removed
  const blobUrls = new Map();

  // --- DOM helpers ---

  // Remove all descendant entries from `nodes` and revoke their blob URLs.
  // Called before clearing or removing an element that may have registered children.
  function cleanDescendants(parentEl) {
    for (const [id, node] of nodes) {
      if (id !== 0 && node !== parentEl && parentEl.contains(node)) {
        const oldUrl = blobUrls.get(id);
        if (oldUrl) { URL.revokeObjectURL(oldUrl); blobUrls.delete(id); }
        nodes.delete(id);
      }
    }
  }

  // --- DOM flush ---

  function batsDomFlush(bufPtr, len) {
    const mem = new Uint8Array(instance.exports.memory.buffer);
    let pos = 0;

    while (pos < len) {
      const op = mem[bufPtr + pos];
      const nodeId = readI32(mem, bufPtr + pos + 1);

      switch (op) {
        case 4: { // CREATE_ELEMENT
          const parentId = readI32(mem, bufPtr + pos + 5);
          const tagLen = mem[bufPtr + pos + 9];
          const tag = new TextDecoder().decode(mem.slice(bufPtr + pos + 10, bufPtr + pos + 10 + tagLen));
          const el = document.createElement(tag);
          nodes.set(nodeId, el);
          const parent = nodes.get(parentId);
          if (parent) parent.appendChild(el);
          pos += 10 + tagLen;
          break;
        }
        case 1: { // SET_TEXT
          const textLen = mem[bufPtr + pos + 5] | (mem[bufPtr + pos + 6] << 8);
          const text = new TextDecoder().decode(mem.slice(bufPtr + pos + 7, bufPtr + pos + 7 + textLen));
          const el = nodes.get(nodeId);
          if (el) el.textContent = text;
          pos += 7 + textLen;
          break;
        }
        case 2: { // SET_ATTR
          const nameLen = mem[bufPtr + pos + 5];
          const name = new TextDecoder().decode(mem.slice(bufPtr + pos + 6, bufPtr + pos + 6 + nameLen));
          const valOff = pos + 6 + nameLen;
          const valLen = mem[bufPtr + valOff] | (mem[bufPtr + valOff + 1] << 8);
          const value = new TextDecoder().decode(mem.slice(bufPtr + valOff + 2, bufPtr + valOff + 2 + valLen));
          const el = nodes.get(nodeId);
          if (el) el.setAttribute(name, value);
          pos += 6 + nameLen + 2 + valLen;
          break;
        }
        case 3: { // REMOVE_CHILDREN
          const el = nodes.get(nodeId);
          if (el) {
            cleanDescendants(el);
            el.innerHTML = '';
          }
          pos += 5;
          break;
        }
        case 5: { // REMOVE_CHILD
          const el = nodes.get(nodeId);
          if (el) {
            cleanDescendants(el);
            el.remove();
          }
          const oldUrl = blobUrls.get(nodeId);
          if (oldUrl) { URL.revokeObjectURL(oldUrl); blobUrls.delete(nodeId); }
          nodes.delete(nodeId);
          pos += 5;
          break;
        }
        default:
          throw new Error(`Unknown bats DOM op: ${op} at offset ${pos}`);
      }
    }
  }

  // --- Image src (direct bridge call, not diff buffer) ---

  function batsJsSetImageSrc(nodeId, dataPtr, dataLen, mimePtr, mimeLen) {
    const mime = readString(mimePtr, mimeLen);
    const bytes = readBytes(dataPtr, dataLen);
    const oldUrl = blobUrls.get(nodeId);
    if (oldUrl) URL.revokeObjectURL(oldUrl);
    const blob = new Blob([bytes], { type: mime });
    const url = URL.createObjectURL(blob);
    const el = nodes.get(nodeId);
    if (el) el.src = url;
    blobUrls.set(nodeId, url);
  }

  // --- Timer ---

  function batsSetTimer(delayMs, resolverId) {
    setTimeout(() => {
      instance.exports.bats_timer_fire(resolverId);
    }, delayMs);
  }

  // --- IndexedDB ---

  let dbPromise = null;
  function openDB() {
    if (!dbPromise) {
      dbPromise = new Promise((resolve, reject) => {
        const req = indexedDB.open('bats', 1);
        req.onupgradeneeded = () => {
          req.result.createObjectStore('kv');
        };
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
    }
    return dbPromise;
  }

  function batsIdbPut(keyPtr, keyLen, valPtr, valLen, resolverId) {
    const key = readString(keyPtr, keyLen);
    const val = readBytes(valPtr, valLen);
    openDB().then(db => {
      const tx = db.transaction('kv', 'readwrite');
      tx.objectStore('kv').put(val, key);
      tx.oncomplete = () => {
        instance.exports.bats_idb_fire(resolverId, 0);
      };
      tx.onerror = () => {
        instance.exports.bats_idb_fire(resolverId, -1);
      };
    });
  }

  function batsIdbGet(keyPtr, keyLen, resolverId) {
    const key = readString(keyPtr, keyLen);
    openDB().then(db => {
      const tx = db.transaction('kv', 'readonly');
      const req = tx.objectStore('kv').get(key);
      req.onsuccess = () => {
        const result = req.result;
        if (result === undefined) {
          instance.exports.bats_idb_fire_get(resolverId, 0);
        } else {
          const data = new Uint8Array(result);
          const stashId = stashData(data);
          instance.exports.bats_bridge_stash_set_int(1, stashId);
          instance.exports.bats_idb_fire_get(resolverId, data.length);
        }
      };
      req.onerror = () => {
        instance.exports.bats_idb_fire_get(resolverId, 0);
      };
    });
  }

  function batsIdbDelete(keyPtr, keyLen, resolverId) {
    const key = readString(keyPtr, keyLen);
    openDB().then(db => {
      const tx = db.transaction('kv', 'readwrite');
      tx.objectStore('kv').delete(key);
      tx.oncomplete = () => {
        instance.exports.bats_idb_fire(resolverId, 0);
      };
      tx.onerror = () => {
        instance.exports.bats_idb_fire(resolverId, -1);
      };
    });
  }

  // --- Window ---

  function batsJsFocusWindow() {
    try { root.ownerDocument.defaultView.focus(); } catch(e) {}
  }

  function batsJsGetVisibilityState() {
    try {
      return document.visibilityState === 'hidden' ? 1 : 0;
    } catch(e) { return 0; }
  }

  function batsJsLog(level, msgPtr, msgLen) {
    const msg = readString(msgPtr, msgLen);
    const labels = ['debug', 'info', 'warn', 'error'];
    const label = labels[level] || 'log';
    console.log(`[bats:${label}] ${msg}`);
  }

  // --- Navigation ---

  function writeStringToWasm(str, outPtr, maxLen) {
    const encoded = new TextEncoder().encode(str);
    const len = Math.min(encoded.length, maxLen);
    new Uint8Array(instance.exports.memory.buffer).set(encoded.subarray(0, len), outPtr);
    return len;
  }

  function batsJsGetUrl(outPtr, maxLen) {
    try {
      const win = root.ownerDocument.defaultView;
      return writeStringToWasm(win.location.href, outPtr, maxLen);
    } catch(e) { return 0; }
  }

  function batsJsGetUrlHash(outPtr, maxLen) {
    try {
      const win = root.ownerDocument.defaultView;
      return writeStringToWasm(win.location.hash, outPtr, maxLen);
    } catch(e) { return 0; }
  }

  function batsJsSetUrlHash(hashPtr, hashLen) {
    try {
      const win = root.ownerDocument.defaultView;
      win.location.hash = readString(hashPtr, hashLen);
    } catch(e) {}
  }

  function batsJsReplaceState(urlPtr, urlLen) {
    try {
      const win = root.ownerDocument.defaultView;
      win.history.replaceState(null, '', readString(urlPtr, urlLen));
    } catch(e) {}
  }

  function batsJsPushState(urlPtr, urlLen) {
    try {
      const win = root.ownerDocument.defaultView;
      win.history.pushState(null, '', readString(urlPtr, urlLen));
    } catch(e) {}
  }

  // --- DOM read ---

  function batsJsMeasureNode(nodeId) {
    const el = nodes.get(nodeId);
    if (el && typeof el.getBoundingClientRect === 'function') {
      const rect = el.getBoundingClientRect();
      instance.exports.bats_measure_set(0, Math.round(rect.x));
      instance.exports.bats_measure_set(1, Math.round(rect.y));
      instance.exports.bats_measure_set(2, Math.round(rect.width));
      instance.exports.bats_measure_set(3, Math.round(rect.height));
      instance.exports.bats_measure_set(4, el.scrollWidth || 0);
      instance.exports.bats_measure_set(5, el.scrollHeight || 0);
      return 1;
    }
    for (let i = 0; i < 6; i++) {
      instance.exports.bats_measure_set(i, 0);
    }
    return 0;
  }

  function batsJsQuerySelector(selectorPtr, selectorLen) {
    const selector = readString(selectorPtr, selectorLen);
    try {
      const el = document.querySelector(selector);
      if (!el) return -1;
      for (const [id, node] of nodes) {
        if (node === el) return id;
      }
      return -1;
    } catch(e) { return -1; }
  }

  // --- Event listener ---

  const listenerMap = new Map();
  let currentEvent = null;

  // Encode event payload as binary (little-endian).
  // Returns Uint8Array or null for no payload.
  function encodeEventPayload(event, eventType) {
    if (eventType === 'click' || eventType === 'pointerdown' ||
        eventType === 'pointerup' || eventType === 'pointermove') {
      // [f64:clientX] [f64:clientY] [i32:target_node_id]
      const buf = new ArrayBuffer(20);
      const dv = new DataView(buf);
      dv.setFloat64(0, event.clientX || 0, true);
      dv.setFloat64(8, event.clientY || 0, true);
      let targetId = -1;
      if (event.target) {
        for (const [id, node] of nodes) {
          if (node === event.target) { targetId = id; break; }
        }
      }
      dv.setInt32(16, targetId, true);
      return new Uint8Array(buf);
    }
    if (eventType === 'keydown' || eventType === 'keyup') {
      // [u8:keyLen] [bytes:key] [u8:flags]
      const key = event.key || '';
      const keyBytes = new TextEncoder().encode(key);
      const buf = new Uint8Array(1 + keyBytes.length + 1);
      buf[0] = keyBytes.length;
      buf.set(keyBytes, 1);
      const flags = (event.shiftKey ? 1 : 0) | (event.ctrlKey ? 2 : 0) |
                    (event.altKey ? 4 : 0) | (event.metaKey ? 8 : 0);
      buf[1 + keyBytes.length] = flags;
      return buf;
    }
    if (eventType === 'input') {
      // [u16le:value_len] [bytes:value]
      const value = (event.target && event.target.value) || '';
      const valBytes = new TextEncoder().encode(value);
      const buf = new Uint8Array(2 + valBytes.length);
      buf[0] = valBytes.length & 0xFF;
      buf[1] = (valBytes.length >> 8) & 0xFF;
      buf.set(valBytes, 2);
      return buf;
    }
    if (eventType === 'scroll') {
      // [f64:scrollTop] [f64:scrollLeft]
      const buf = new ArrayBuffer(16);
      const dv = new DataView(buf);
      const target = event.target || {};
      dv.setFloat64(0, target.scrollTop || 0, true);
      dv.setFloat64(8, target.scrollLeft || 0, true);
      return new Uint8Array(buf);
    }
    if (eventType === 'resize') {
      // [f64:width] [f64:height]
      const buf = new ArrayBuffer(16);
      const dv = new DataView(buf);
      const win = root.ownerDocument.defaultView || {};
      dv.setFloat64(0, win.innerWidth || 0, true);
      dv.setFloat64(8, win.innerHeight || 0, true);
      return new Uint8Array(buf);
    }
    if (eventType === 'touchstart' || eventType === 'touchend' || eventType === 'touchmove') {
      // [f64:clientX] [f64:clientY] [i32:identifier]
      const touch = (event.touches && event.touches[0]) ||
                    (event.changedTouches && event.changedTouches[0]);
      if (touch) {
        const buf = new ArrayBuffer(20);
        const dv = new DataView(buf);
        dv.setFloat64(0, touch.clientX || 0, true);
        dv.setFloat64(8, touch.clientY || 0, true);
        dv.setInt32(16, touch.identifier || 0, true);
        return new Uint8Array(buf);
      }
      return null;
    }
    if (eventType === 'visibilitychange') {
      // [u8:hidden]
      return new Uint8Array([document.visibilityState === 'hidden' ? 1 : 0]);
    }
    return null;
  }

  function batsJsAddEventListener(nodeId, eventTypePtr, typeLen, listenerId) {
    const node = nodes.get(nodeId);
    if (!node) return;
    const eventType = readString(eventTypePtr, typeLen);
    const handler = (event) => {
      currentEvent = event;
      const payload = encodeEventPayload(event, eventType);
      if (payload) {
        const stashId = stashData(payload);
        instance.exports.bats_bridge_stash_set_int(1, stashId);
      }
      instance.exports.bats_on_event(listenerId, payload ? payload.length : 0);
      currentEvent = null;
    };
    listenerMap.set(listenerId, { node, eventType, handler });
    node.addEventListener(eventType, handler);
  }

  function batsJsRemoveEventListener(listenerId) {
    const entry = listenerMap.get(listenerId);
    if (entry) {
      entry.node.removeEventListener(entry.eventType, entry.handler);
      listenerMap.delete(listenerId);
    }
  }

  function batsJsPreventDefault() {
    if (currentEvent) currentEvent.preventDefault();
  }

  // --- Fetch ---

  function batsJsFetch(urlPtr, urlLen, resolverId) {
    const url = readString(urlPtr, urlLen);
    fetch(url).then(async (response) => {
      const body = new Uint8Array(await response.arrayBuffer());
      if (body.length > 0) {
        const stashId = stashData(body);
        instance.exports.bats_bridge_stash_set_int(1, stashId);
      }
      instance.exports.bats_on_fetch_complete(resolverId, response.status, body.length);
    }).catch(() => {
      instance.exports.bats_on_fetch_complete(resolverId, 0, 0);
    });
  }

  // --- Clipboard ---

  function batsJsClipboardWriteText(textPtr, textLen, resolverId) {
    const text = readString(textPtr, textLen);
    try {
      const win = root.ownerDocument.defaultView;
      if (win && win.navigator && win.navigator.clipboard) {
        win.navigator.clipboard.writeText(text).then(
          () => { instance.exports.bats_on_clipboard_complete(resolverId, 1); },
          () => { instance.exports.bats_on_clipboard_complete(resolverId, 0); }
        );
      } else {
        instance.exports.bats_on_clipboard_complete(resolverId, 0);
      }
    } catch(e) {
      instance.exports.bats_on_clipboard_complete(resolverId, 0);
    }
  }

  // --- File ---

  const fileCache = new Map();
  let nextFileHandle = 1;

  function batsJsFileOpen(inputNodeId, resolverId) {
    const el = nodes.get(inputNodeId);
    if (!el || !el.files || !el.files[0]) {
      instance.exports.bats_bridge_stash_set_int(2, 0);
      instance.exports.bats_on_file_open(resolverId, 0, 0);
      return;
    }
    const file = el.files[0];
    const reader = new FileReader();
    reader.onload = () => {
      const handle = nextFileHandle++;
      const data = new Uint8Array(reader.result);
      fileCache.set(handle, data);
      const nameBytes = new TextEncoder().encode(file.name);
      const nameStashId = stashData(nameBytes);
      instance.exports.bats_bridge_stash_set_int(1, nameStashId);
      instance.exports.bats_bridge_stash_set_int(2, nameBytes.length);
      instance.exports.bats_on_file_open(resolverId, handle, data.length);
    };
    reader.onerror = () => {
      instance.exports.bats_bridge_stash_set_int(2, 0);
      instance.exports.bats_on_file_open(resolverId, 0, 0);
    };
    reader.readAsArrayBuffer(file);
  }

  function batsJsFileRead(handle, fileOffset, len, outPtr) {
    const data = fileCache.get(handle);
    if (!data) return 0;
    const available = Math.max(0, data.length - fileOffset);
    const copyLen = Math.min(len, available);
    if (copyLen > 0) {
      new Uint8Array(instance.exports.memory.buffer).set(
        data.subarray(fileOffset, fileOffset + copyLen), outPtr);
    }
    return copyLen;
  }

  function batsJsFileClose(handle) {
    fileCache.delete(handle);
  }

  // --- Decompress ---

  const blobCache = new Map();
  let nextBlobHandle = 1;

  function batsJsDecompress(dataPtr, dataLen, method, resolverId) {
    const compressed = readBytes(dataPtr, dataLen);
    const formats = ['gzip', 'deflate', 'deflate-raw'];
    const format = formats[method];
    if (!format || typeof DecompressionStream === 'undefined') {
      instance.exports.bats_on_decompress_complete(resolverId, 0, 0);
      return;
    }
    const ds = new DecompressionStream(format);
    const writer = ds.writable.getWriter();
    writer.write(compressed);
    writer.close();
    const reader = ds.readable.getReader();
    const chunks = [];
    (function pump() {
      reader.read().then(({ done, value }) => {
        if (value) chunks.push(value);
        if (done) {
          let totalLen = 0;
          for (const c of chunks) totalLen += c.length;
          const result = new Uint8Array(totalLen);
          let off = 0;
          for (const c of chunks) { result.set(c, off); off += c.length; }
          const handle = nextBlobHandle++;
          blobCache.set(handle, result);
          instance.exports.bats_on_decompress_complete(resolverId, handle, result.length);
        } else {
          pump();
        }
      }).catch(() => {
        instance.exports.bats_on_decompress_complete(resolverId, 0, 0);
      });
    })();
  }

  function batsJsBlobRead(handle, blobOffset, len, outPtr) {
    const data = blobCache.get(handle);
    if (!data) return 0;
    const available = Math.max(0, data.length - blobOffset);
    const copyLen = Math.min(len, available);
    if (copyLen > 0) {
      new Uint8Array(instance.exports.memory.buffer).set(
        data.subarray(blobOffset, blobOffset + copyLen), outPtr);
    }
    return copyLen;
  }

  function batsJsBlobFree(handle) {
    blobCache.delete(handle);
  }

  // --- Notification/Push ---

  function batsJsNotificationRequestPermission(resolverId) {
    if (typeof Notification === 'undefined') {
      instance.exports.bats_on_permission_result(resolverId, 0);
      return;
    }
    Notification.requestPermission().then((perm) => {
      instance.exports.bats_on_permission_result(resolverId, perm === 'granted' ? 1 : 0);
    }).catch(() => {
      instance.exports.bats_on_permission_result(resolverId, 0);
    });
  }

  function batsJsNotificationShow(titlePtr, titleLen) {
    if (typeof Notification === 'undefined') return;
    const title = readString(titlePtr, titleLen);
    try { new Notification(title); } catch(e) {}
  }

  function batsJsPushSubscribe(vapidPtr, vapidLen, resolverId) {
    try {
      const vapidBytes = readBytes(vapidPtr, vapidLen);
      navigator.serviceWorker.ready.then((reg) => {
        return reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: vapidBytes,
        });
      }).then((sub) => {
        const json = JSON.stringify(sub.toJSON());
        const jsonBytes = new TextEncoder().encode(json);
        const stashId = stashData(jsonBytes);
        instance.exports.bats_bridge_stash_set_int(1, stashId);
        instance.exports.bats_on_push_subscribe(resolverId, jsonBytes.length);
      }).catch(() => {
        instance.exports.bats_on_push_subscribe(resolverId, 0);
      });
    } catch(e) {
      instance.exports.bats_on_push_subscribe(resolverId, 0);
    }
  }

  function batsJsPushGetSubscription(resolverId) {
    try {
      navigator.serviceWorker.ready.then((reg) => {
        return reg.pushManager.getSubscription();
      }).then((sub) => {
        if (!sub) {
          instance.exports.bats_on_push_subscribe(resolverId, 0);
          return;
        }
        const json = JSON.stringify(sub.toJSON());
        const jsonBytes = new TextEncoder().encode(json);
        const stashId = stashData(jsonBytes);
        instance.exports.bats_bridge_stash_set_int(1, stashId);
        instance.exports.bats_on_push_subscribe(resolverId, jsonBytes.length);
      }).catch(() => {
        instance.exports.bats_on_push_subscribe(resolverId, 0);
      });
    } catch(e) {
      instance.exports.bats_on_push_subscribe(resolverId, 0);
    }
  }

  // --- HTML parsing ---

  // Tags filtered out during parsing (security/sanitization)
  const FILTERED_TAGS = new Set([
    'script', 'iframe', 'object', 'embed', 'form', 'input', 'link', 'meta'
  ]);

  function batsJsParseHtml(htmlPtr, htmlLen) {
    const html = readString(htmlPtr, htmlLen);
    let doc;
    try {
      const win = root.ownerDocument.defaultView;
      if (typeof win.DOMParser !== 'undefined') {
        doc = new win.DOMParser().parseFromString(html, 'text/html');
      } else {
        return 0;
      }
    } catch(e) { return 0; }

    // Serialize DOM tree to binary SAX format
    const chunks = [];
    let totalLen = 0;

    function pushByte(b) { chunks.push(new Uint8Array([b])); totalLen += 1; }
    function pushU16LE(v) { chunks.push(new Uint8Array([v & 0xFF, (v >> 8) & 0xFF])); totalLen += 2; }
    function pushBytes(arr) { chunks.push(arr); totalLen += arr.length; }

    function serializeNode(node) {
      if (node.nodeType === 1) { // ELEMENT_NODE
        const tag = node.tagName.toLowerCase();
        if (FILTERED_TAGS.has(tag)) return;
        const tagBytes = new TextEncoder().encode(tag);
        if (tagBytes.length > 255) return;

        // Collect safe attributes
        const attrs = [];
        for (let i = 0; i < node.attributes.length; i++) {
          const attr = node.attributes[i];
          if (/^on/i.test(attr.name)) continue;    // skip event handlers
          if (attr.name === 'style') continue;       // skip style
          if (!/^[a-zA-Z0-9-]+$/.test(attr.name)) continue; // skip non-safe names
          const nameBytes = new TextEncoder().encode(attr.name);
          const valBytes = new TextEncoder().encode(attr.value);
          if (nameBytes.length > 255 || valBytes.length > 65535) continue;
          attrs.push({ nameBytes, valBytes });
        }

        // ELEMENT_OPEN: [0x01] [u8:tag_len] [bytes:tag] [u8:attr_count]
        pushByte(0x01);
        pushByte(tagBytes.length);
        pushBytes(tagBytes);
        pushByte(attrs.length);

        // per attr: [u8:name_len] [bytes:name] [u16le:value_len] [bytes:value]
        for (const a of attrs) {
          pushByte(a.nameBytes.length);
          pushBytes(a.nameBytes);
          pushU16LE(a.valBytes.length);
          pushBytes(a.valBytes);
        }

        // Recurse children
        for (let i = 0; i < node.childNodes.length; i++) {
          serializeNode(node.childNodes[i]);
        }

        // ELEMENT_CLOSE: [0x02]
        pushByte(0x02);
      } else if (node.nodeType === 3) { // TEXT_NODE
        const text = node.textContent || '';
        if (text.length === 0) return;
        const textBytes = new TextEncoder().encode(text);
        if (textBytes.length > 65535) return;
        // TEXT: [0x03] [u16le:text_len] [bytes:text]
        pushByte(0x03);
        pushU16LE(textBytes.length);
        pushBytes(textBytes);
      }
    }

    // Serialize body children (skip <html>, <head>, <body> wrappers)
    const body = doc.body;
    if (body) {
      for (let i = 0; i < body.childNodes.length; i++) {
        serializeNode(body.childNodes[i]);
      }
    }

    if (totalLen === 0) return 0;

    // Combine chunks and stash for WASM to pull
    const combined = new Uint8Array(totalLen);
    let off = 0;
    for (const chunk of chunks) {
      combined.set(chunk, off);
      off += chunk.length;
    }
    const stashId = stashData(combined);
    instance.exports.bats_bridge_stash_set_int(1, stashId);
    return totalLen;
  }

  const imports = {
    env: {
      ...extraImports,
      bats_dom_flush: batsDomFlush,
      bats_js_set_image_src: batsJsSetImageSrc,
      bats_set_timer: batsSetTimer,
      bats_exit: () => { resolveDone(); },
      // IDB
      bats_idb_js_put: batsIdbPut,
      bats_idb_js_get: batsIdbGet,
      bats_idb_js_delete: batsIdbDelete,
      // Window
      bats_js_focus_window: batsJsFocusWindow,
      bats_js_get_visibility_state: batsJsGetVisibilityState,
      bats_js_log: batsJsLog,
      // Navigation
      bats_js_get_url: batsJsGetUrl,
      bats_js_get_url_hash: batsJsGetUrlHash,
      bats_js_set_url_hash: batsJsSetUrlHash,
      bats_js_replace_state: batsJsReplaceState,
      bats_js_push_state: batsJsPushState,
      // DOM read
      bats_js_measure_node: batsJsMeasureNode,
      bats_js_query_selector: batsJsQuerySelector,
      // Event listener
      bats_js_add_event_listener: batsJsAddEventListener,
      bats_js_remove_event_listener: batsJsRemoveEventListener,
      bats_js_prevent_default: batsJsPreventDefault,
      // Fetch
      bats_js_fetch: batsJsFetch,
      // Clipboard
      bats_js_clipboard_write_text: batsJsClipboardWriteText,
      // File
      bats_js_file_open: batsJsFileOpen,
      bats_js_file_read: batsJsFileRead,
      bats_js_file_close: batsJsFileClose,
      // Decompress
      bats_js_decompress: batsJsDecompress,
      bats_js_blob_read: batsJsBlobRead,
      bats_js_blob_free: batsJsBlobFree,
      // Notification/Push
      bats_js_notification_request_permission: batsJsNotificationRequestPermission,
      bats_js_notification_show: batsJsNotificationShow,
      bats_js_push_subscribe: batsJsPushSubscribe,
      bats_js_push_get_subscription: batsJsPushGetSubscription,
      // HTML parsing
      bats_js_parse_html: batsJsParseHtml,
      // Data stash
      bats_js_stash_read: batsJsStashRead,
    },
  };

  const result = await WebAssembly.instantiate(wasmBytes, imports);
  instance = result.instance;
  instance.exports.bats_node_init(0);

  return { exports: instance.exports, nodes, done };
}
