(* scroll -- scroll operations for bridge *)

#include "share/atspre_staload.hats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

#pub fun scroll_to
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni,
   x: int, y: int): void

#pub fun scroll_into_view
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni,
   smooth: int): void

#pub fun set_scroll_top
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni,
   value: int): void

#pub fun set_scroll_left
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni,
   value: int): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_js_scroll_to(void*, int, int, int);
extern void bats_js_scroll_into_view(void*, int, int);
extern void bats_js_set_scroll_top(void*, int, int);
extern void bats_js_set_scroll_left(void*, int, int);
%}
extern fun _bats_js_scroll_to
  (id: ptr, id_len: int, x: int, y: int): void = "mac#bats_js_scroll_to"
extern fun _bats_js_scroll_into_view
  (id: ptr, id_len: int, smooth: int): void = "mac#bats_js_scroll_into_view"
extern fun _bats_js_set_scroll_top
  (id: ptr, id_len: int, value: int): void = "mac#bats_js_set_scroll_top"
extern fun _bats_js_set_scroll_left
  (id: ptr, id_len: int, value: int): void = "mac#bats_js_set_scroll_left"

implement scroll_to{li}{ni}(node_id, id_len, x, y) =
  _bats_js_scroll_to(
    $UNSAFE.castvwtp1{ptr}(node_id), id_len, x, y)

implement scroll_into_view{li}{ni}(node_id, id_len, smooth) =
  _bats_js_scroll_into_view(
    $UNSAFE.castvwtp1{ptr}(node_id), id_len, smooth)

implement set_scroll_top{li}{ni}(node_id, id_len, value) =
  _bats_js_set_scroll_top(
    $UNSAFE.castvwtp1{ptr}(node_id), id_len, value)

implement set_scroll_left{li}{ni}(node_id, id_len, value) =
  _bats_js_set_scroll_left(
    $UNSAFE.castvwtp1{ptr}(node_id), id_len, value)

end (* $UNSAFE *)
end (* #target wasm *)
