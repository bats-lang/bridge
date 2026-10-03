(* dom -- DOM flush, image src, click for bridge *)

#include "share/atspre_staload.hats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

(* Applies a stream of DOM operations, each addressed by element id,
   in order: SET_TEXT (1), SET_ATTR (2), REMOVE_CHILDREN (3),
   CREATE_ELEMENT (4), REMOVE_CHILD (5), APPEND_TEXT (6), REMOVE_ATTR
   (7), CLONE_NODE (8), SET_SCROLL_LEFT (11), SET_SCROLL_TOP (12) and
   the canvas operations (64 to 84). An id is a u16 length (little
   endian) and its bytes. 9 and 10 are not used: 9 was a scroll of both
   axes in 2026.10.3.72358, so a stream written for that shape stops
   at an unknown operation rather than being misread.

   CLONE_NODE ([8][id][source id][parent id]) puts a deep copy of
   element source, as earlier operations of the flush left it, at the
   end of element parent's children, the copy taking the id. The
   elements inside the copy lose their ids, since an id names one
   element; so what they need can come only from the copy itself or
   from stylesheet rules keyed on it. Inert on the copy takes its whole
   subtree out of focus, clicks and the accessibility tree, but it does
   not stop what moves by itself: a medium with autoplay (it loads and
   plays), a marquee, an animated image, a CSS animation. A source that
   may hold them needs the app to remove them from the copy (or the
   source to have none). An id reference inside the copy (aria-*,
   href="#...", url(#...)) still names the source's element. A copy
   given an id already in the document makes a second element with it,
   as CREATE_ELEMENT does.

   The copy's ordinary tree keeps only what the stream itself could
   make: HTML elements (CREATE_ELEMENT makes no SVG or MathML), none
   that CREATE_ELEMENT refuses, none with an is attribute (a customized
   built-in, which the stream never makes) or an open shadow root, and
   no attribute that SET_ATTR refuses. An element left out goes with
   everything inside it; when source is one, nothing is made. A closed
   shadow root cannot be seen from the page, so it is outside this
   check; the stream makes no shadow root (it never attaches one, and
   template is refused). What else the copy keeps or loses is the app's
   to say, with the other operations on its id.

   SET_SCROLL_LEFT and SET_SCROLL_TOP ([11 or 12][id][i32 value],
   little endian) set the element's scrollLeft or scrollTop: one write, at its
   place in the flush, so an element made earlier in the same flush can
   be scrolled. The write lays the page out then, so it should come
   after every operation that sizes the element (or its scroll range is
   still the old one). The scroll imports (scroll.bats) write at once,
   while a flush is still being written, so a scroll in a batch belongs
   in the stream *)
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

(* Shows text as marked (a highlight of this kind, styled with the CSS
   ::highlight(bats-mark-<kind>) pseudo-element): from offset soff of
   element sid's first text node to offset eoff of element eid's. The
   page is not changed; where the browser has no Custom Highlight API
   nothing is shown. *)
#pub fun mark_range
  {ls,le:agz}{ns,ne:pos}
  (kind: int, sid: !$A.borrow(byte, ls, ns), slen: int ns, soff: int,
   eid: !$A.borrow(byte, le, ne), elen: int ne, eoff: int): void

(* Removes every mark of this kind *)
#pub fun clear_marks (kind: int): void

(* Moves the keyboard focus to the element *)
#pub fun focus_node
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_dom_flush(void*, int);
extern void bats_js_set_image_src(void*, int, void*, int, void*, int);
extern void bats_js_click_node(void*, int);
extern void bats_js_mark_range(int, void*, int, int, void*, int, int);
extern void bats_js_clear_marks(int);
extern void bats_js_focus_node(void*, int);
%}
extern fun _bats_dom_flush
  (buf: ptr, len: int): void = "mac#bats_dom_flush"
extern fun _bats_js_set_image_src
  (id: ptr, id_len: int, data: ptr, data_len: int, mime: ptr, mime_len: int)
  : void = "mac#bats_js_set_image_src"
extern fun _bats_js_click_node
  (id: ptr, id_len: int): void = "mac#bats_js_click_node"
extern fun _bats_js_mark_range
  (kind: int, sid: ptr, slen: int, soff: int, eid: ptr, elen: int, eoff: int)
  : void = "mac#bats_js_mark_range"
extern fun _bats_js_clear_marks
  (kind: int): void = "mac#bats_js_clear_marks"
extern fun _bats_js_focus_node
  (id: ptr, id_len: int): void = "mac#bats_js_focus_node"

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

implement mark_range{ls,le}{ns,ne}(kind, sid, slen, soff, eid, elen, eoff) =
  _bats_js_mark_range(kind,
    $UNSAFE.castvwtp1{ptr}(sid), slen, soff,
    $UNSAFE.castvwtp1{ptr}(eid), elen, eoff)

implement clear_marks(kind) = _bats_js_clear_marks(kind)

implement focus_node{li}{ni}(node_id, id_len) =
  _bats_js_focus_node($UNSAFE.castvwtp1{ptr}(node_id), id_len)

end (* $UNSAFE *)
end (* #target wasm *)
