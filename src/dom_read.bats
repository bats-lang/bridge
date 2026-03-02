(* dom_read -- DOM measurement, query, text content, selection for bridge *)

#include "share/atspre_staload.hats"

#use array as A
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

#pub fun measure
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni): $R.result(int, int)

#pub fun get_measure_x(): int

#pub fun get_measure_y(): int

#pub fun get_measure_w(): int

#pub fun get_measure_h(): int

#pub fun get_measure_scroll_w(): int

#pub fun get_measure_scroll_h(): int

#pub fun query_selector
  {lb:agz}{n:pos}
  (sel: !$A.borrow(byte, lb, n), sel_len: int n): $R.option(int)

#pub fun caret_position_from_point
  (x: int, y: int): int

#pub fun read_text_content
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni): int

#pub fun read_text_content_get
  : {n:pos | n <= 1048576}
  (int n) -> [l:agz] $A.arr(byte, l, n)

#pub fun measure_text_offset
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni,
   offset: int): int

#pub fun get_selection_text(): int

#pub fun get_selection_text_get
  : {n:pos | n <= 1048576}
  (int n) -> [l:agz] $A.arr(byte, l, n)

#pub fun get_selection_rect(): void

#pub fun get_selection_range(): void

(* Read form input .value into WASM memory. Returns byte length. *)
#pub fun read_input_value
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni,
   max_len: int): int

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
extern fun _bats_js_measure_node
  (id: ptr, id_len: int): int = "mac#bats_js_measure_node"
extern fun _bats_js_query_selector
  (selector: ptr, selector_len: int): int = "mac#bats_js_query_selector"
extern fun _bats_js_caret_position_from_point
  (x: int, y: int): int = "mac#bats_js_caret_position_from_point"
extern fun _bats_js_read_text_content
  (id: ptr, id_len: int): int = "mac#bats_js_read_text_content"
extern fun _bats_js_measure_text_offset
  (id: ptr, id_len: int, offset: int): int = "mac#bats_js_measure_text_offset"
extern fun _bats_js_get_selection_text
  (): int = "mac#bats_js_get_selection_text"
extern fun _bats_js_get_selection_rect
  (): void = "mac#bats_js_get_selection_rect"
extern fun _bats_js_get_selection_range
  (): void = "mac#bats_js_get_selection_range"
extern fun _bats_js_read_input_value
  (id: ptr, id_len: int, dest: ptr, max_len: int): int = "mac#bats_js_read_input_value"
end

implement measure{li}{ni}(node_id, id_len) = let
  val r = _bats_js_measure_node(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement get_measure_x() = $UNSAFE begin $extfcall(int, "bats_bridge_measure_get", 0) end
implement get_measure_y() = $UNSAFE begin $extfcall(int, "bats_bridge_measure_get", 1) end
implement get_measure_w() = $UNSAFE begin $extfcall(int, "bats_bridge_measure_get", 2) end
implement get_measure_h() = $UNSAFE begin $extfcall(int, "bats_bridge_measure_get", 3) end
implement get_measure_scroll_w() = $UNSAFE begin $extfcall(int, "bats_bridge_measure_get", 4) end
implement get_measure_scroll_h() = $UNSAFE begin $extfcall(int, "bats_bridge_measure_get", 5) end

implement query_selector{lb}{n}(sel, sel_len) = let
  val r = _bats_js_query_selector(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(sel) end,
    sel_len)
in
  if r >= 0 then $R.some(r) else $R.none()
end

implement caret_position_from_point(x, y) =
  _bats_js_caret_position_from_point(x, y)

implement read_text_content{li}{ni}(node_id, id_len) =
  _bats_js_read_text_content(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len)

implement read_text_content_get{n}(len) =
  stash_read(stash_get_int(1), len)

implement measure_text_offset{li}{ni}(node_id, id_len, offset) =
  _bats_js_measure_text_offset(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len, offset)

implement get_selection_text() =
  _bats_js_get_selection_text()

implement get_selection_text_get{n}(len) =
  stash_read(stash_get_int(1), len)

implement get_selection_rect() =
  _bats_js_get_selection_rect()

implement get_selection_range() =
  _bats_js_get_selection_range()

implement read_input_value{li}{ni}(node_id, id_len, max_len) =
  _bats_js_read_input_value(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len, the_null_ptr, max_len)

end (* #target wasm *)
