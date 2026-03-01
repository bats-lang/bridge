(* dom_read -- DOM measurement, query, text content, selection for bridge *)

#include "share/atspre_staload.hats"

#use array as A
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

#pub fun measure
  (node_id: int): $R.result(int, int)

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
  (node_id: int): int

#pub fun read_text_content_get
  {n:pos | n <= 1048576}
  (len: int n): [l:agz] $A.arr(byte, l, n)

#pub fun measure_text_offset
  (node_id: int, offset: int): int

#pub fun get_selection_text(): int

#pub fun get_selection_text_get
  {n:pos | n <= 1048576}
  (len: int n): [l:agz] $A.arr(byte, l, n)

#pub fun get_selection_rect(): void

#pub fun get_selection_range(): void

(* Read form input .value into WASM memory. Returns byte length. *)
#pub fun read_input_value
  (node_id: int, max_len: int): int

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin

extern fun _bats_js_measure_node
  (node_id: int): int = "mac#bats_js_measure_node"
extern fun _bats_js_query_selector
  (selector: ptr, selector_len: int): int = "mac#bats_js_query_selector"
extern fun _bats_js_caret_position_from_point
  (x: int, y: int): int = "mac#bats_js_caret_position_from_point"
extern fun _bats_js_read_text_content
  (node_id: int): int = "mac#bats_js_read_text_content"
extern fun _bats_js_measure_text_offset
  (node_id: int, offset: int): int = "mac#bats_js_measure_text_offset"
extern fun _bats_js_get_selection_text
  (): int = "mac#bats_js_get_selection_text"
extern fun _bats_js_get_selection_rect
  (): void = "mac#bats_js_get_selection_rect"
extern fun _bats_js_get_selection_range
  (): void = "mac#bats_js_get_selection_range"

implement measure(node_id) = let
  val r = _bats_js_measure_node(node_id)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement get_measure_x() = $extfcall(int, "bats_bridge_measure_get", 0)
implement get_measure_y() = $extfcall(int, "bats_bridge_measure_get", 1)
implement get_measure_w() = $extfcall(int, "bats_bridge_measure_get", 2)
implement get_measure_h() = $extfcall(int, "bats_bridge_measure_get", 3)
implement get_measure_scroll_w() = $extfcall(int, "bats_bridge_measure_get", 4)
implement get_measure_scroll_h() = $extfcall(int, "bats_bridge_measure_get", 5)

implement query_selector{lb}{n}(sel, sel_len) = let
  val r = _bats_js_query_selector(
    $UNSAFE.castvwtp1{ptr}(sel),
    sel_len)
in
  if r >= 0 then $R.some(r) else $R.none()
end

implement caret_position_from_point(x, y) =
  _bats_js_caret_position_from_point(x, y)

implement read_text_content(node_id) =
  _bats_js_read_text_content(node_id)

implement read_text_content_get{n}(len) =
  stash_read(stash_get_int(1), len)

implement measure_text_offset(node_id, offset) =
  _bats_js_measure_text_offset(node_id, offset)

implement get_selection_text() =
  _bats_js_get_selection_text()

implement get_selection_text_get{n}(len) =
  stash_read(stash_get_int(1), len)

implement get_selection_rect() =
  _bats_js_get_selection_rect()

implement get_selection_range() =
  _bats_js_get_selection_range()

extern fun _bats_js_read_input_value
  (node_id: int, dest: ptr, max_len: int): int = "mac#bats_js_read_input_value"

implement read_input_value(node_id, max_len) =
  _bats_js_read_input_value(node_id, the_null_ptr, max_len)

end (* $UNSAFE *)
end (* #target wasm *)
