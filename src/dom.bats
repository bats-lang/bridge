(* dom -- DOM flush and image src for bridge *)

#include "share/atspre_staload.hats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

#pub fun dom_flush
  {l:agz}{n:nat}{m:nat | m <= n}
  (buf: !$A.arr(byte, l, n), len: int m): void

#pub fun click_node(node_id: int): void

#pub fun set_image_src
  {ld:agz}{nd:pos}{lm:agz}{nm:pos}
  (node_id: int,
   data: !$A.borrow(byte, ld, nd), data_len: int nd,
   mime: !$A.borrow(byte, lm, nm), mime_len: int nm): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin

extern fun _bats_dom_flush
  (buf: ptr, len: int): void = "mac#bats_dom_flush"
extern fun _bats_js_set_image_src
  (node_id: int, data: ptr, data_len: int, mime: ptr, mime_len: int)
  : void = "mac#bats_js_set_image_src"

implement dom_flush{l}{n}{m}(buf, len) =
  _bats_dom_flush(
    $UNSAFE.castvwtp1{ptr}(buf),
    len)

implement set_image_src{ld}{nd}{lm}{nm}
  (node_id, data, data_len, mime, mime_len) =
  _bats_js_set_image_src(node_id,
    $UNSAFE.castvwtp1{ptr}(data), data_len,
    $UNSAFE.castvwtp1{ptr}(mime), mime_len)

extern fun _bats_js_click_node
  (node_id: int): void = "mac#bats_js_click_node"

implement click_node(node_id) = _bats_js_click_node(node_id)

end (* $UNSAFE *)
end (* #target wasm *)
