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

(* Shows a copy of element source in element holder, in place of
   holder's children: what source shows now, scrolled as it is, which
   does not change after (a snapshot that is still live DOM, such as
   the page being turned away from, laid over the page). The copy has
   no id, nor any inside it (source keeps them all, so an id still
   names one element), no tabindex and no data-gesture-region; it is
   inert and aria-hidden, so it can neither be focused nor read out *)
#pub fun copy_node
  {ls,lh:agz}{ns,nh:pos}
  (source: !$A.borrow(byte, ls, ns), source_len: int ns,
   holder: !$A.borrow(byte, lh, nh), holder_len: int nh): void

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
extern void bats_js_copy_node(void*, int, void*, int);
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
extern fun _bats_js_copy_node
  (source: ptr, source_len: int, holder: ptr, holder_len: int): void = "mac#bats_js_copy_node"

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

implement copy_node{ls,lh}{ns,nh}(source, source_len, holder, holder_len) =
  _bats_js_copy_node(
    $UNSAFE.castvwtp1{ptr}(source), source_len,
    $UNSAFE.castvwtp1{ptr}(holder), holder_len)

end (* $UNSAFE *)
end (* #target wasm *)
