(* impl -- bridge function implementations *)

#include "share/atspre_staload.hats"

#use array as A
#use promise as P
#use result as R

staload "./lib.sats"
staload _ = "./lib.dats"

(* --- Timer --- *)

implement timer_set(delay_ms, stash_id) =
  _bats_set_timer(delay_ms, stash_id)

implement exit() = _bats_exit()

(* --- DOM --- *)

implement dom_flush{l}{n}{m}(buf, len) =
  _bats_dom_flush(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(buf) end,
    len)

implement set_image_src{ld}{nd}{lm}{nm}
  (node_id, data, data_len, mime, mime_len) =
  _bats_js_set_image_src(node_id,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end, data_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(mime) end, mime_len)

(* --- DOM read --- *)

implement measure(node_id) = let
  val r = _bats_js_measure_node(node_id)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement get_measure_x() = $extfcall(int, "_bridge_measure_get", 0)
implement get_measure_y() = $extfcall(int, "_bridge_measure_get", 1)
implement get_measure_w() = $extfcall(int, "_bridge_measure_get", 2)
implement get_measure_h() = $extfcall(int, "_bridge_measure_get", 3)
implement get_measure_scroll_w() = $extfcall(int, "_bridge_measure_get", 4)
implement get_measure_scroll_h() = $extfcall(int, "_bridge_measure_get", 5)

implement query_selector{lb}{n}(sel, sel_len) = let
  val r = _bats_js_query_selector(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(sel) end,
    sel_len)
in
  if r >= 0 then $R.some(r) else $R.none()
end

(* --- Event --- *)

implement listen{lb}{n}(node_id, event_type, type_len, listener_id) =
  _bats_js_add_event_listener(node_id,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(event_type) end,
    type_len, listener_id)

implement unlisten(listener_id) =
  _bats_js_remove_event_listener(listener_id)

implement prevent_default() = _bats_js_prevent_default()

implement listener_set(id, cb) =
  $extfcall(void, "bats_listener_set", id, cb)

implement listener_set_closure(id, cb) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(cb) end
in $extfcall(void, "bats_listener_set", id, cbp) end

implement listener_clear(id) =
  $extfcall(void, "bats_listener_set", id, the_null_ptr)

implement listener_get(id) =
  $extfcall(ptr, "bats_listener_get", id)

(* --- Navigation --- *)

implement get_url{l}{n}(out, max_len) = let
  val r = _bats_js_get_url(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end,
    max_len)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement get_hash{l}{n}(out, max_len) = let
  val r = _bats_js_get_url_hash(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end,
    max_len)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement set_hash{lb}{n}(hash, hash_len) =
  _bats_js_set_url_hash(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(hash) end,
    hash_len)

implement replace_state{lb}{n}(url, url_len) =
  _bats_js_replace_state(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end,
    url_len)

implement push_state{lb}{n}(url, url_len) =
  _bats_js_push_state(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end,
    url_len)

(* --- Window --- *)

implement focus() = _bats_js_focus_window()

implement get_visibility() = _bats_js_get_visibility_state()

implement log{lb}{n}(level, msg, msg_len) =
  _bats_js_log(level,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(msg) end,
    msg_len)

(* --- IDB --- *)

implement idb_put{lk}{nk}{lv}{nv}
  (key, key_len, val_data, val_len, stash_id) =
  _bats_idb_js_put(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(val_data) end, val_len,
    stash_id)

implement idb_get{lk}{nk}(key, key_len, stash_id) =
  _bats_idb_js_get(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    stash_id)

implement idb_get_result{n}(len) =
  _bridge_recv(_stash_get_int(1), len)

implement idb_delete{lk}{nk}(key, key_len, stash_id) =
  _bats_idb_js_delete(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    stash_id)

(* --- Fetch --- *)

implement fetch_req{lb}{n}(url, url_len, stash_id) =
  _bats_js_fetch(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end, url_len,
    stash_id)

implement fetch_body_len() = _stash_get_int(0)

implement fetch_body{n}(len) =
  _bridge_recv(_stash_get_int(1), len)

(* --- Clipboard --- *)

implement clipboard_write{lb}{n}(text, text_len, stash_id) =
  _bats_js_clipboard_write_text(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(text) end, text_len,
    stash_id)

(* --- File --- *)

implement file_open(input_node_id, stash_id) =
  _bats_js_file_open(input_node_id, stash_id)

implement file_size() = _stash_get_int(0)

implement file_name_len() = _stash_get_int(2)

implement file_name{n}(len) =
  _bridge_recv(_stash_get_int(1), len)

implement file_read{l}{n}(handle, file_offset, out, len) = let
  val r = _bats_js_file_read(handle, file_offset, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement file_close(handle) = _bats_js_file_close(handle)

(* --- Decompress --- *)

implement decompress_req{lb}{n}(data, data_len, method, stash_id) =
  _bats_js_decompress(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end,
    data_len, method, stash_id)

implement decompress_len() = _stash_get_int(0)

implement blob_read{l}{n}(handle, blob_offset, out, len) = let
  val r = _bats_js_blob_read(handle, blob_offset, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement blob_free(handle) = _bats_js_blob_free(handle)

(* --- Notify --- *)

implement notify_request(stash_id) =
  _bats_js_notification_request_permission(stash_id)

implement notify_show{lb}{n}(title, title_len) =
  _bats_js_notification_show(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(title) end,
    title_len)

implement notify_subscribe{lb}{n}(vapid, vapid_len, stash_id) =
  _bats_js_push_subscribe(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(vapid) end,
    vapid_len, stash_id)

implement notify_result{n}(len) =
  _bridge_recv(_stash_get_int(1), len)

implement notify_get_sub(stash_id) =
  _bats_js_push_get_subscription(stash_id)

(* --- XML --- *)

implement xml_parse{lb}{n}(html, len) =
  _bats_js_parse_html(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(html) end,
    len)

implement xml_result{n}(len) =
  _bridge_recv(_stash_get_int(1), len)

(* --- Stash --- *)

implement stash_read{n}(stash_id, len) =
  _bridge_recv(stash_id, len)

implement stash_set_int(slot, v0) = _stash_set_int(slot, v0)

implement stash_get_int(slot) = _stash_get_int(slot)

(* --- WASM exports --- *)

implement on_timer_fire(resolver_id) =
  $P.fire(resolver_id, 0)

implement on_event(listener_id, payload_len) = let
  val cbp = $extfcall(ptr, "bats_listener_get", listener_id)
in
  if ptr_isnot_null(cbp) then let
    val cb = $UNSAFE begin $UNSAFE.cast{(int) -<cloref1> int}(cbp) end
    val _ = cb(payload_len)
  in () end
  else ()
end

implement on_fetch_complete(resolver_id, status, body_len) = let
  val () = _stash_set_int(0, body_len)
in $P.fire(resolver_id, status) end

implement on_clipboard_complete(resolver_id, success) =
  $P.fire(resolver_id, success)

implement on_file_open(resolver_id, handle, size) = let
  val () = _stash_set_int(0, size)
in $P.fire(resolver_id, handle) end

implement on_decompress_complete(resolver_id, handle, decompressed_len) = let
  val () = _stash_set_int(0, decompressed_len)
in $P.fire(resolver_id, handle) end

implement on_idb_fire(resolver_id, status) =
  $P.fire(resolver_id, status)

implement on_idb_fire_get(resolver_id, data_len) =
  $P.fire(resolver_id, data_len)

implement on_permission_result(resolver_id, granted) =
  $P.fire(resolver_id, granted)

implement on_push_subscribe(resolver_id, json_len) =
  $P.fire(resolver_id, json_len)
