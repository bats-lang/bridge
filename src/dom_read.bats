(* dom_read -- DOM measurement, query, text content, selection for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* Whether a measure found its element. JS's answer is decoded here,
   once: anything but its 1 is NoElement (the slots then hold 0s). *)
#pub datatype measured =
  | Measured
  | NoElement

(* The element's box (slots 0 to 3: x, y, width, height) and its scroll
   size (4, 5), read with get_measure_* *)
#pub fun measure
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni): measured

(* The last measure's values, as the page reported them: any int *)
#pub fun get_measure_x(): [v:int] int v

#pub fun get_measure_y(): [v:int] int v

#pub fun get_measure_w(): [v:int] int v

#pub fun get_measure_h(): [v:int] int v

#pub fun get_measure_scroll_w(): [v:int] int v

#pub fun get_measure_scroll_h(): [v:int] int v

(* The id of the first element the selector matches, as a blob; none
   when nothing matches or the element has no id *)
#pub fun query_selector
  {lb:agz}{n:pos}
  (sel: !$A.borrow(byte, lb, n), sel_len: int n)
  : $R.option([k:nat] dblob(k))

(* The offset of the caret at viewport point (x, y) in its text node;
   none when there is none *)
#pub fun caret_position_from_point
  (x: int, y: int): $R.option([v:nat] int v)

(* The node's text content as a blob; none when there is no such node
   or its text is empty *)
(* The id of the element at viewport point (x, y), or of its nearest
   ancestor that has one; none when there is none *)
#pub fun element_at_point
  (x: int, y: int): $R.option([k:nat] dblob(k))

#pub fun read_text_content
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni)
  : $R.option([k:nat] dblob(k))

(* Where the offset-th character of the element's first text node is
   (slots 0 and 1: x, y); NoElement when there is no such element or
   text *)
#pub fun measure_text_offset
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni,
   offset: int): measured

(* The selected text as a blob; none when the selection is empty *)
#pub fun get_selection_text(): $R.option([k:nat] dblob(k))

#pub fun get_selection_rect(): void

(* The selection's start and end offsets go to measure slots 0 and 1;
   the ids of the elements it starts and ends in are returned as blobs
   (none when there is no selection or the element has no id) *)
#pub fun get_selection_range()
  : @($R.option([k:nat] dblob(k)), $R.option([k:nat] dblob(k)))

(* A form input's value as a blob; none when there is no such input or
   its value is empty *)
#pub fun read_input_value
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni)
  : $R.option([k:nat] dblob(k))

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern int bats_bridge_measure_get(int slot);
extern void bats_measure_set(int slot, int v);
extern int bats_js_measure_node(void*, int);
extern int bats_js_query_selector(void*, int);
extern int bats_js_caret_position_from_point(int, int);
extern int bats_js_read_text_content(void*, int);
extern int bats_js_measure_text_offset(void*, int, int);
extern int bats_js_get_selection_text(void);
extern int bats_js_element_at_point(int, int);
extern void bats_js_get_selection_rect(void);
extern void bats_js_get_selection_range(void);
extern int bats_js_read_input_value(void*, int);
%}
extern fun _bats_js_measure_node
  (id: ptr, id_len: int): int = "mac#bats_js_measure_node"
extern fun _bats_js_query_selector
  (selector: ptr, selector_len: int): [v:int] int v = "mac#bats_js_query_selector"
extern fun _bats_js_caret_position_from_point
  (x: int, y: int): [v:int] int v = "mac#bats_js_caret_position_from_point"
extern fun _bats_js_read_text_content
  (id: ptr, id_len: int): [v:int] int v = "mac#bats_js_read_text_content"
extern fun _bats_js_measure_text_offset
  (id: ptr, id_len: int, offset: int): int = "mac#bats_js_measure_text_offset"
extern fun _bats_js_element_at_point
  (x: int, y: int): [v:int] int v = "mac#bats_js_element_at_point"
extern fun _bats_js_get_selection_text
  (): [v:int] int v = "mac#bats_js_get_selection_text"
extern fun _bats_js_get_selection_rect
  (): void = "mac#bats_js_get_selection_rect"
extern fun _bats_js_get_selection_range
  (): void = "mac#bats_js_get_selection_range"
extern fun _bats_js_read_input_value
  (id: ptr, id_len: int): [v:int] int v = "mac#bats_js_read_input_value"
end

(* JS's codes: 1 measured; 0 (measure) or -1 (measure_text_offset) no
   element *)
fn _measured (code: int): measured =
  if code = 1 then Measured() else NoElement()

implement measure{li}{ni}(node_id, id_len) =
  _measured(_bats_js_measure_node(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len))

implement get_measure_x() = $UNSAFE begin $extfcall([v:int] int v, "bats_bridge_measure_get", 0) end
implement get_measure_y() = $UNSAFE begin $extfcall([v:int] int v, "bats_bridge_measure_get", 1) end
implement get_measure_w() = $UNSAFE begin $extfcall([v:int] int v, "bats_bridge_measure_get", 2) end
implement get_measure_h() = $UNSAFE begin $extfcall([v:int] int v, "bats_bridge_measure_get", 3) end
implement get_measure_scroll_w() = $UNSAFE begin $extfcall([v:int] int v, "bats_bridge_measure_get", 4) end
implement get_measure_scroll_h() = $UNSAFE begin $extfcall([v:int] int v, "bats_bridge_measure_get", 5) end

fn _measure_set (slot: int, v: int): void =
  $UNSAFE begin $extfcall(void, "bats_measure_set", slot, v) end

implement query_selector{lb}{n}(sel, sel_len) =
  blob_claim(_bats_js_query_selector(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(sel) end,
    sel_len))

(* JS's -1 (or any negative) is none *)
implement caret_position_from_point(x, y) = let
  val offset = _bats_js_caret_position_from_point(x, y)
in if offset >= 0 then $R.some(offset) else $R.none() end

implement element_at_point(x, y) =
  blob_claim(_bats_js_element_at_point(x, y))

implement read_text_content{li}{ni}(node_id, id_len) =
  blob_claim(_bats_js_read_text_content(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len))

implement measure_text_offset{li}{ni}(node_id, id_len, offset) =
  _measured(_bats_js_measure_text_offset(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len, offset))

implement get_selection_text() =
  blob_claim(_bats_js_get_selection_text())

implement get_selection_rect() =
  _bats_js_get_selection_rect()

implement get_selection_range() = let
  (* Measure slots 2 and 3 are cleared first, so a range that sets
     nothing claims no stale handle *)
  val () = _measure_set(2, 0)
  val () = _measure_set(3, 0)
  val () = _bats_js_get_selection_range()
  val s = blob_claim(get_measure_w())
  val e = blob_claim(get_measure_h())
in @(s, e) end

implement read_input_value{li}{ni}(node_id, id_len) =
  blob_claim(_bats_js_read_input_value(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len))

end (* #target wasm *)
