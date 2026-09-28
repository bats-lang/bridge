(* event -- DOM event listener management for bridge *)

#include "share/atspre_staload.hats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

(* The event's payload as JS passes it to a listener: a handle to claim
   with blob_claim (decompress.bats) during the callback, 0 when the
   event has none. Each event's payload is its own blob, and one not
   claimed during its callback is dropped. *)
#pub typedef event_payload = [v:int] int v

(* A listener id indexes bridge's listener table (128 slots, shared with
   listen_media), so it is proven to be in range. *)
#pub typedef listener_id = [i:nat | i < 128] int i

#pub fun listen
  {li:agz}{ni:pos}{lb:agz}{n:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni,
   event_type: !$A.borrow(byte, lb, n), type_len: int n,
   listener_id: listener_id,
   callback: (event_payload) -<cloref1> int): void

#pub fun listen_document
  {lb:agz}{n:pos}
  (event_type: !$A.borrow(byte, lb, n), type_len: int n,
   listener_id: listener_id,
   callback: (event_payload) -<cloref1> int): void

(* A listener on the window (resize fires there, not on the document) *)
#pub fun listen_window
  {lb:agz}{n:pos}
  (event_type: !$A.borrow(byte, lb, n), type_len: int n,
   listener_id: listener_id,
   callback: (event_payload) -<cloref1> int): void

(* A listener for files handed to the app from outside it (an Android
   intent to open or share a file): each file's handle is the payload,
   to claim with file_claim (file.bats). Files that came before the
   listener are passed to it as soon as it is set. *)
#pub fun listen_external_files
  (listener_id: listener_id,
   callback: (event_payload) -<cloref1> int): void

(* Pointer events for the gestures package, on node_id (a stable root:
   an element a DOM diff does not replace): down, move, up and cancel
   (moves only for a pointer down; a mouse only while its primary button
   is held, and captured to the root once it has moved 4 px, so a plain
   click keeps its own target), a cancel of all on
   visibilitychange, window blur or a lost capture, a region's rendered
   offset on a down while its transition is in flight, and scrollend,
   transitionend and transitioncancel of a region (an element with
   data-gesture-region). They are batched and passed once per animation
   frame, with a tick each frame while a pointer is down, as one blob of
   32-byte records (gestures' decode.bats) *)
#pub fun listen_gestures
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni,
   listener_id: listener_id,
   callback: (event_payload) -<cloref1> int): void

#pub fun unlisten
  (listener_id: listener_id): void

#pub fun prevent_default(): void

#pub fun on_event
  (listener_id: int, payload: event_payload): void = "ext#bats_on_event"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_listener_set(int id, void *cb);
extern void *bats_listener_get(int id);
extern void bats_js_add_event_listener(void*, int, void*, int, int);
extern void bats_js_add_document_listener(void*, int, int);
extern void bats_js_remove_event_listener(int);
extern void bats_js_add_window_listener(void*, int, int);
extern void bats_js_listen_external_files(int);
extern void bats_js_listen_gestures(void*, int, int);
extern void bats_js_prevent_default(void);
%}
extern fun _bats_js_add_event_listener
  (id: ptr, id_len: int, event_type: ptr, type_len: int, listener_id: int)
  : void = "mac#bats_js_add_event_listener"
extern fun _bats_js_add_document_listener
  (event_type: ptr, type_len: int, listener_id: int)
  : void = "mac#bats_js_add_document_listener"
extern fun _bats_js_add_window_listener
  (event_type: ptr, type_len: int, listener_id: int)
  : void = "mac#bats_js_add_window_listener"
extern fun _bats_js_listen_gestures
  (id: ptr, id_len: int, listener_id: int): void = "mac#bats_js_listen_gestures"
extern fun _bats_js_listen_external_files
  (listener_id: int): void = "mac#bats_js_listen_external_files"
extern fun _bats_js_remove_event_listener
  (listener_id: int): void = "mac#bats_js_remove_event_listener"
extern fun _bats_js_prevent_default
  (): void = "mac#bats_js_prevent_default"
end

implement listen{li}{ni}{lb}{n}
  (node_id, id_len, event_type, type_len, listener_id, callback) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val () = $UNSAFE begin $extfcall(void, "bats_listener_set", listener_id, cbp) end
in _bats_js_add_event_listener(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(event_type) end,
    type_len, listener_id) end

implement listen_document{lb}{n}
  (event_type, type_len, listener_id, callback) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val () = $UNSAFE begin $extfcall(void, "bats_listener_set", listener_id, cbp) end
in _bats_js_add_document_listener(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(event_type) end,
    type_len, listener_id) end

implement listen_window{lb}{n}
  (event_type, type_len, listener_id, callback) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val () = $UNSAFE begin $extfcall(void, "bats_listener_set", listener_id, cbp) end
in _bats_js_add_window_listener(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(event_type) end,
    type_len, listener_id) end

implement listen_external_files(listener_id, callback) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val () = $UNSAFE begin $extfcall(void, "bats_listener_set", listener_id, cbp) end
in _bats_js_listen_external_files(listener_id) end

implement listen_gestures{li}{ni}(node_id, id_len, listener_id, callback) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val () = $UNSAFE begin $extfcall(void, "bats_listener_set", listener_id, cbp) end
in _bats_js_listen_gestures(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len, listener_id) end

implement unlisten(listener_id) = let
  val () = $UNSAFE begin $extfcall(void, "bats_listener_set", listener_id, the_null_ptr) end
in _bats_js_remove_event_listener(listener_id) end

implement prevent_default() = _bats_js_prevent_default()

implement on_event(listener_id, payload) = let
  val cbp = $UNSAFE begin $extfcall(ptr, "bats_listener_get", listener_id) end
in
  if ptr_isnot_null(cbp) then let
    val cb = $UNSAFE begin $UNSAFE.cast{(event_payload) -<cloref1> int}(cbp) end
    val _ = cb(payload)
  in () end
  else ()
end

end (* #target wasm *)
