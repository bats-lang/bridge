(* event -- DOM event listener management for bridge *)

#include "share/atspre_staload.hats"
staload "./stash.bats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

#pub fun listen
  {li:agz}{ni:pos}{lb:agz}{n:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni,
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
  : {n:pos | n <= 1048576}
  (int n) -> [l:agz] $A.arr(byte, l, n)

#pub fun on_event
  (listener_id: int, payload_len: int): void = "ext#bats_on_event"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_listener_set(int id, void *cb);
extern void *bats_listener_get(int id);
extern int bats_bridge_stash_get_int(int slot);
extern void bats_js_add_event_listener(void*, int, void*, int, int);
extern void bats_js_add_document_listener(void*, int, int);
extern void bats_js_remove_event_listener(int);
extern void bats_js_prevent_default(void);
%}
extern fun _bats_js_add_event_listener
  (id: ptr, id_len: int, event_type: ptr, type_len: int, listener_id: int)
  : void = "mac#bats_js_add_event_listener"
extern fun _bats_js_add_document_listener
  (event_type: ptr, type_len: int, listener_id: int)
  : void = "mac#bats_js_add_document_listener"
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

implement unlisten(listener_id) = let
  val () = $UNSAFE begin $extfcall(void, "bats_listener_set", listener_id, the_null_ptr) end
in _bats_js_remove_event_listener(listener_id) end

implement prevent_default() = _bats_js_prevent_default()

implement get_payload{n}(len) = let
  val sid = $UNSAFE begin $extfcall(int, "bats_bridge_stash_get_int", 1) end
in stash_read(sid, len) end

implement on_event(listener_id, payload_len) = let
  val cbp = $UNSAFE begin $extfcall(ptr, "bats_listener_get", listener_id) end
in
  if ptr_isnot_null(cbp) then let
    val cb = $UNSAFE begin $UNSAFE.cast{(int) -<cloref1> int}(cbp) end
    val _ = cb(payload_len)
  in () end
  else ()
end

end (* #target wasm *)
