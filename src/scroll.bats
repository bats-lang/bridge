(* scroll -- scroll operations for bridge *)

#include "share/atspre_staload.hats"

(* ============================================================
   Public API
   ============================================================ *)

#pub fun scroll_to
  (node_id: int, x: int, y: int): void

#pub fun scroll_into_view
  (node_id: int, smooth: int): void

#pub fun set_scroll_top
  (node_id: int, value: int): void

#pub fun set_scroll_left
  (node_id: int, value: int): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin

extern fun _bats_js_scroll_to
  (node_id: int, x: int, y: int): void = "mac#bats_js_scroll_to"
extern fun _bats_js_scroll_into_view
  (node_id: int, smooth: int): void = "mac#bats_js_scroll_into_view"
extern fun _bats_js_set_scroll_top
  (node_id: int, value: int): void = "mac#bats_js_set_scroll_top"
extern fun _bats_js_set_scroll_left
  (node_id: int, value: int): void = "mac#bats_js_set_scroll_left"

implement scroll_to(node_id, x, y) =
  _bats_js_scroll_to(node_id, x, y)

implement scroll_into_view(node_id, smooth) =
  _bats_js_scroll_into_view(node_id, smooth)

implement set_scroll_top(node_id, value) =
  _bats_js_set_scroll_top(node_id, value)

implement set_scroll_left(node_id, value) =
  _bats_js_set_scroll_left(node_id, value)

end (* $UNSAFE *)
end (* #target wasm *)
