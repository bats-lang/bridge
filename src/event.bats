(* event -- DOM event listener management for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* The event's payload, given to its listener for the time of the call:
   its bytes, when the event has any, are taken with event_take during
   the call (JS drops them when it returns). It is not a number: it
   cannot be compared or computed with *)
#pub abst@ype event_payload = int

(* The payload's bytes, a blob of their own size; none when the event
   has none, or they were taken already *)
#pub fun event_take (payload: event_payload): $R.option([k:nat] dblob(k))

(* A listener id indexes bridge's listener table (128 slots, shared with
   listen_media), so it is proven to be in range. *)
#pub typedef listener_id = [i:nat | i < 128] int i

(* A listener is a linear closure, made with llam: bridge keeps it in
   its slot and frees it when the slot is set again or unlistened (only
   once no listener is running, so a listener may unlisten itself).
   wasm has no garbage collector: a lam closure could never be freed. *)

#pub fun listen
  {li:agz}{ni:pos}{lb:agz}{n:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni,
   event_type: !$A.borrow(byte, lb, n), type_len: int n,
   listener_id: listener_id,
   callback: (event_payload) -<lincloptr1> int): void

#pub fun listen_document
  {lb:agz}{n:pos}
  (event_type: !$A.borrow(byte, lb, n), type_len: int n,
   listener_id: listener_id,
   callback: (event_payload) -<lincloptr1> int): void

(* A listener on the window (resize fires there, not on the document) *)
#pub fun listen_window
  {lb:agz}{n:pos}
  (event_type: !$A.borrow(byte, lb, n), type_len: int n,
   listener_id: listener_id,
   callback: (event_payload) -<lincloptr1> int): void

(* Pointer events on node_id (a stable root: an element a DOM diff does
   not replace), one raw record each as it comes (the gestures package's
   RAW_RECORD: twelve int32 LE, read by its gestures_raw): down, move,
   up and cancel (a mouse only with its button), its lost capture, the
   page hidden or the window's focus lost, and scrollend, transitionend
   and transitioncancel inside it. A down carries the innermost
   data-gesture-region hit (-1 for none), the viewport's width, and
   whether that region has a transition running and its translate then;
   a transition's end is sent only for a region's own element. Positions
   are in 1/16 CSS px, times in ms. Batching, ticks, capture and
   cancelling are the gestures package's (its pointer source) *)
#pub fun listen_pointer
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni,
   listener_id: listener_id,
   callback: (event_payload) -<lincloptr1> int): void

(* Captures pointer id to node_id (setPointerCapture), as the gestures
   source asks (CapturePointer) *)
#pub fun pointer_capture
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni, pointer_id: int): void

(* Removes the listener, and frees its closure *)
#pub fun unlisten
  (listener_id: listener_id): void

#pub fun prevent_default(): void

#pub fun on_event
  (listener_id: int, payload: Int): void = "ext#bats_on_event"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_listener_set(int id, void *cb);
extern void *bats_listener_get(int id);
extern void bats_listener_enter(void);
extern void bats_listener_leave(void);
extern void bats_js_add_event_listener(void*, int, void*, int, int);
extern void bats_js_add_document_listener(void*, int, int);
extern void bats_js_remove_event_listener(int);
extern void bats_js_add_window_listener(void*, int, int);
extern void bats_js_listen_pointer(void*, int, int);
extern void bats_js_pointer_capture(void*, int, int);
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
extern fun _bats_js_listen_pointer
  (id: ptr, id_len: int, listener_id: int): void = "mac#bats_js_listen_pointer"
extern fun _bats_js_pointer_capture
  (id: ptr, id_len: int, pointer_id: int): void = "mac#bats_js_pointer_capture"
extern fun _bats_js_remove_event_listener
  (listener_id: int): void = "mac#bats_js_remove_event_listener"
extern fun _bats_js_prevent_default
  (): void = "mac#bats_js_prevent_default"

(* JS's handle to the event's bytes, 0 when it has none *)
assume event_payload = [v:int] int v
end

implement event_take(payload) = blob_claim(payload)

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

implement listen_pointer{li}{ni}(node_id, id_len, listener_id, callback) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val () = $UNSAFE begin $extfcall(void, "bats_listener_set", listener_id, cbp) end
in _bats_js_listen_pointer(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len, listener_id) end

implement pointer_capture{li}{ni}(node_id, id_len, pointer_id) =
  _bats_js_pointer_capture(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len, pointer_id)

implement unlisten(listener_id) = let
  val () = $UNSAFE begin $extfcall(void, "bats_listener_set", listener_id, the_null_ptr) end
in _bats_js_remove_event_listener(listener_id) end

implement prevent_default() = _bats_js_prevent_default()

(* The slot keeps the closure: it is called through the pointer, and
   freed only when the slot lets it go *)
implement on_event(listener_id, payload) = let
  val cbp = $UNSAFE begin $extfcall(ptr, "bats_listener_get", listener_id) end
in
  if ptr_isnot_null(cbp) then let
    val () = $UNSAFE begin $extfcall(void, "bats_listener_enter") end
    val cb = $UNSAFE begin $UNSAFE.cast{(event_payload) -<cloref1> int}(cbp) end
    val _ = cb(payload)
  in $UNSAFE begin $extfcall(void, "bats_listener_leave") end end
  else ()
end

end (* #target wasm *)
