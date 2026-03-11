(* dom -- DOM flush, image src, click for bridge *)

#include "share/atspre_staload.hats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

#pub fun dom_flush
  {l:agz}{n:nat}{m:nat | m <= n}
  (buf: !$A.arr(byte, l, n), len: int m): void

#pub fun click_node
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni): void

#pub fun set_image_src
  {li:agz}{ni:pos}{ld:agz}{nd:pos}{lm:agz}{nm:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni,
   data: !$A.borrow(byte, ld, nd), data_len: int nd,
   mime: !$A.borrow(byte, lm, nm), mime_len: int nm): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_dom_flush(void*, int);
extern void bats_js_set_image_src(void*, int, void*, int, void*, int);
extern void bats_js_click_node(void*, int);
%}
extern fun _bats_dom_flush
  (buf: ptr, len: int): void = "mac#bats_dom_flush"
extern fun _bats_js_set_image_src
  (id: ptr, id_len: int, data: ptr, data_len: int, mime: ptr, mime_len: int)
  : void = "mac#bats_js_set_image_src"
extern fun _bats_js_click_node
  (id: ptr, id_len: int): void = "mac#bats_js_click_node"

implement dom_flush{l}{n}{m}(buf, len) =
  _bats_dom_flush(
    $UNSAFE.castvwtp1{ptr}(buf),
    len)

implement set_image_src{li}{ni}{ld}{nd}{lm}{nm}
  (node_id, id_len, data, data_len, mime, mime_len) =
  _bats_js_set_image_src(
    $UNSAFE.castvwtp1{ptr}(node_id), id_len,
    $UNSAFE.castvwtp1{ptr}(data), data_len,
    $UNSAFE.castvwtp1{ptr}(mime), mime_len)

implement click_node{li}{ni}(node_id, id_len) =
  _bats_js_click_node(
    $UNSAFE.castvwtp1{ptr}(node_id), id_len)

end (* $UNSAFE *)
end (* #target wasm *)
