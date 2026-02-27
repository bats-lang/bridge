(* event -- DOM event listener management for bridge *)

#include "share/atspre_staload.hats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

#pub fun listen
  {lb:agz}{n:pos}
  (node_id: int,
   event_type: !$A.borrow(byte, lb, n), type_len: int n,
   listener_id: int,
   callback: (int) -<cloref1> int): void

#pub fun listen_document
  {lb:agz}{n:pos}
  (event_type: !$A.borrow(byte, lb, n), type_len: int n,
   listener_id: int,
   callback: (int) -<cloref1> int): void

#pub fun unlisten
  (listener_id: int): void

#pub fun prevent_default(): void

#pub fun get_payload
  {n:pos | n <= 1048576}
  (len: int n): [l:agz] $A.arr(byte, l, n)

#pub fun on_event
  (listener_id: int, payload_len: int): void = "ext#bats_on_event"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

extern fun _bats_js_add_event_listener
  (node_id: int, event_type: ptr, type_len: int, listener_id: int)
  : void = "mac#bats_js_add_event_listener"
extern fun _bats_js_add_document_listener
  (event_type: ptr, type_len: int, listener_id: int)
  : void = "mac#bats_js_add_document_listener"
extern fun _bats_js_remove_event_listener
  (listener_id: int): void = "mac#bats_js_remove_event_listener"
extern fun _bats_js_prevent_default
  (): void = "mac#bats_js_prevent_default"

implement listen{lb}{n}
  (node_id, event_type, type_len, listener_id, callback) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val () = $extfcall(void, "bats_listener_set", listener_id, cbp)
in _bats_js_add_event_listener(node_id,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(event_type) end,
    type_len, listener_id) end

implement listen_document{lb}{n}
  (event_type, type_len, listener_id, callback) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val () = $extfcall(void, "bats_listener_set", listener_id, cbp)
in _bats_js_add_document_listener(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(event_type) end,
    type_len, listener_id) end

implement unlisten(listener_id) = let
  val () = $extfcall(void, "bats_listener_set", listener_id, the_null_ptr)
in _bats_js_remove_event_listener(listener_id) end

implement prevent_default() = _bats_js_prevent_default()

implement get_payload{n}(len) = let
  val sid = $extfcall(int, "bats_bridge_stash_get_int", 1)
in stash_read(sid, len) end

implement on_event(listener_id, payload_len) = let
  val cbp = $extfcall(ptr, "bats_listener_get", listener_id)
in
  if ptr_isnot_null(cbp) then let
    val cb = $UNSAFE begin $UNSAFE.cast{(int) -<cloref1> int}(cbp) end
    val _ = cb(payload_len)
  in () end
  else ()
end

end (* #target wasm *)
