(* book_content -- the book stream, its encoders and opcodes 13 to 20 (keyword: book content) *)

#include "share/atspre_staload.hats"
staload "./outside.bats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

(* The book stream: a buffer of DOM operations that only bridge's encoders
   below write, so a raw byte buffer cannot carry opcodes 13 to 20. Ordinary
   dom_flush refuses them. dom_flush_book applies the stream, and an encoder
   flushes it by itself when the next operation does not fit, which the
   operations being whole by themselves allows.

   The book opcodes:
   CREATE_BOOK_CONTAINER (13) [13][id][parent id][u8 layout 1 or 2]: a div with
   that id, data-book-container and data-book-layout, contain: layout paint
   style and isolation: isolate as inline important declarations (set again
   after any write of style to it), appended to the parent. Refused when the id
   is not a letter and then letters, digits or hyphens, when an element with
   that id is in the document, when the parent is missing or inside a container.
   CREATE_BOOK_ELEMENT (14) [14][container][id][parent][u8 tag length][tag]
   [u8 name length][name]: an element of that tag with data-book-element name,
   under a parent that is the container or a book element of it.
   SET_BOOK_STYLE (15) [15][container][id][u16 length][declarations] and
   SET_BOOK_NAMES (16) [16][container][id][u8 kind 1 class, 2 id, 3 epub:type]
   [u16 length][names]: on a book element of the container.
   BOOK_SHEET_TEXT (17) [17][container][u16 length][bytes], repeated, then
   BOOK_SHEET_END (18) [18][container]: the sheet's text, checked as a whole
   at the end and adopted as @layer book{...}.
   BOOK_STYLE_TEXT (19) [19][container][id][u16 length][bytes], repeated, then
   BOOK_STYLE_END (20) [20][container][id]: the style of a book element in
   pieces (as 17 and 18 are the sheet's), checked as a whole at the end as
   opcode 15 checks its declarations and set as the style attribute.
   A container's ordinary operations: SET_ATTR and REMOVE_ATTR of style, and of
   any data-book-* name, are refused on an element inside a container other than
   the container itself, and data-book-* on every element, in both flushes; a
   CLONE_NODE copy that is not inside the source's container loses style and
   its data-book-*; removing a container drops its sheets and faces *)
#pub absvtype book_stream = ptr

#pub fun book_stream_new (): book_stream

#pub fun book_stream_free (s: book_stream): void

#pub fun dom_flush_book (s: !book_stream): void

(* A container id: a letter, then letters, digits or hyphens. The encoder of
   opcode 13 takes the id only with this proof, made by book_id_scan *)
#pub dataprop BOOK_ID_START(int) =
  | {c:int | 65 <= c; c <= 90} BOOK_ID_START_upper(c)
  | {c:int | 97 <= c; c <= 122} BOOK_ID_START_lower(c)

#pub dataprop BOOK_ID_CH(int) =
  | {c:int} BOOK_ID_CH_start(c) of BOOK_ID_START(c)
  | {c:int | 48 <= c; c <= 57} BOOK_ID_CH_digit(c)
  | BOOK_ID_CH_hyphen(45)

(* k bytes from o, each a letter, a digit or a hyphen *)
#pub dataprop BOOK_ID_REST(cs: $A.cells, o: int, k: int) =
  | {cs:$A.cells}{o:int} BOOK_ID_REST_nil(cs, o, 0)
  | {cs:$A.cells}{o:int}{k:nat}{c:int}
    BOOK_ID_REST_snoc(cs, o, k + 1) of (BOOK_ID_REST(cs, o, k), $A.NTH(cs, o + k, c), BOOK_ID_CH(c))

(* The n bytes of cs are a container id *)
#pub dataprop BOOK_ID(cs: $A.cells, n: int) =
  | {cs:$A.cells}{k:nat}{c:int}
    BOOK_ID_mk(cs, k + 1) of ($A.NTH(cs, 0, c), BOOK_ID_START(c), BOOK_ID_REST(cs, 1, k))

#pub dataprop BOOK_ID_OPT(cs: $A.cells, n: int, b: bool) =
  | {cs:$A.cells}{n:int} BOOK_ID_yes(cs, n, true) of BOOK_ID(cs, n)
  | {cs:$A.cells}{n:int} BOOK_ID_no(cs, n, false)

(* Whether the n bytes are a container id, with the proof when they are *)
#pub fun book_id_scan
  {l:agz}{n:pos}{cs:$A.cells}
  (src: !$A.cborrow(l, n, cs), len: int n): [b:bool] (BOOK_ID_OPT(cs, n, b) | bool b)

(* Opcode 13: a container for the chapter of the outside document doc, under
   the element parent. layout is 1 (reflow) or 2 (fixed) *)
#pub fun book_container
  {l:agz}{n:nat}{cs:$A.cells}{lc:agz}{nc:pos | nc <= 64}{csc:$A.cells}{lp:agz}{np:pos | np <= 1024}{g:int | g == 1 || g == 2}
  (from: OUTSIDE_READ(cs), id_ok: BOOK_ID(csc, nc) |
   s: !book_stream, doc: !$A.cborrow(l, n, cs),
   id: !$A.cborrow(lc, nc, csc), id_len: int nc, parent: !$A.borrow(byte, lp, np), parent_len: int np,
   layout: int g): void

(* Opcode 14: a book element, named (data-book-element) by src[name_off, name_off + name_len) *)
#pub fun book_element
  {l:agz}{n:nat}{cs:$A.cells}{lc:agz}{nc:pos | nc <= 64}{li:agz}{ni:pos | ni <= 1024}{lp:agz}{np:pos | np <= 1024}
  {lt:agz}{nt:pos | nt <= 255}{o,k:nat | o + k <= n; k <= 255}
  (from: OUTSIDE_READ(cs) |
   s: !book_stream, container: !$A.borrow(byte, lc, nc), container_len: int nc,
   id: !$A.borrow(byte, li, ni), id_len: int ni,
   parent: !$A.borrow(byte, lp, np), parent_len: int np,
   tag: !$A.borrow(byte, lt, nt), tag_len: int nt,
   src: !$A.cborrow(l, n, cs), name_off: int o, name_len: int k): void

(* Opcode 15: the declarations src[off, off + len) as the style of a book element *)
#pub fun book_style
  {l:agz}{n:nat}{cs:$A.cells}{lc:agz}{nc:pos | nc <= 64}{li:agz}{ni:pos | ni <= 1024}{o,k:nat | o + k <= n; k <= 65535}
  (from: OUTSIDE_READ(cs) |
   s: !book_stream, container: !$A.borrow(byte, lc, nc), container_len: int nc,
   id: !$A.borrow(byte, li, ni), id_len: int ni,
   src: !$A.cborrow(l, n, cs), off: int o, len: int k): void

(* Opcode 16: the book's class names (kind 1), id (2) or epub:type (3) of a book element *)
#pub fun book_names
  {l:agz}{n:nat}{cs:$A.cells}{lc:agz}{nc:pos | nc <= 64}{li:agz}{ni:pos | ni <= 1024}{kind:int | 1 <= kind; kind <= 3}{o,k:nat | o + k <= n; k <= 65535}
  (from: OUTSIDE_READ(cs) |
   s: !book_stream, container: !$A.borrow(byte, lc, nc), container_len: int nc,
   id: !$A.borrow(byte, li, ni), id_len: int ni, kind: int kind,
   src: !$A.cborrow(l, n, cs), off: int o, len: int k): void

(* Opcode 17: a piece of the sheet's text that is a span of outside bytes *)
#pub fun book_sheet_span
  {l:agz}{n:nat}{cs:$A.cells}{lc:agz}{nc:pos | nc <= 64}{o,k:nat | o + k <= n; k <= 65535}
  (from: OUTSIDE_READ(cs) |
   s: !book_stream, container: !$A.borrow(byte, lc, nc), container_len: int nc,
   src: !$A.cborrow(l, n, cs), off: int o, len: int k): void

(* Opcode 17: a piece that is a literal of the program (punctuation, a property
   name, a rewritten selector part, a face name) *)
#pub fun book_sheet_lit
  {lc:agz}{nc:pos | nc <= 64}{m:nat | m <= 1024}
  (s: !book_stream, container: !$A.borrow(byte, lc, nc), container_len: int nc,
   lit: string m): void

(* Opcode 17: a piece that is the container's own id: the bytes of the container
   operand, written as the sheet's text as well as the name of the sheet's
   container (the prefix [data-book-container="<id>"] that the sheet's selectors
   start with). The id is the operand itself (a borrow is linear: it cannot be
   passed twice), so the id of another container cannot be given, and the
   proposition about outside bytes is not used (keyword: book sheet id) *)
#pub fun book_sheet_id
  {lc:agz}{nc:pos | nc <= 64}
  (s: !book_stream, container: !$A.borrow(byte, lc, nc), container_len: int nc): void

(* Opcode 18: the sheet is whole *)
#pub fun book_sheet_end
  {lc:agz}{nc:pos | nc <= 64}
  (s: !book_stream, container: !$A.borrow(byte, lc, nc), container_len: int nc): void

(* A style in pieces (opcodes 19 and 20, keyword: book style pieces): the style
   attribute of the book element id of the container, written as the pieces in
   order and then the end, checked as a whole as opcode 15 checks its
   declarations. The run is a linear token made by book_style_begin, which
   fixes the container and the element by their borrows: every piece and the end
   take the same two borrows (a different container or element does not
   type-check) and the end consumes the run, so a style that is never ended does
   not type-check. Opcode 15 and book_style are beside them, as they were *)
#pub datavtype book_style_run(lc: addr, li: addr) =
  | {lc,li:addr} book_style_run_mk(lc, li)

#pub fun book_style_begin
  {lc:agz}{nc:pos | nc <= 64}{li:agz}{ni:pos | ni <= 1024}
  (container: !$A.borrow(byte, lc, nc), id: !$A.borrow(byte, li, ni)): book_style_run(lc, li)

(* Opcode 19: a piece that is a span of outside bytes *)
#pub fun book_style_span
  {l:agz}{n:nat}{cs:$A.cells}{lc:agz}{nc:pos | nc <= 64}{li:agz}{ni:pos | ni <= 1024}{o,k:nat | o + k <= n; k <= 65535}
  (from: OUTSIDE_READ(cs) |
   s: !book_stream, run: !book_style_run(lc, li),
   container: !$A.borrow(byte, lc, nc), container_len: int nc,
   id: !$A.borrow(byte, li, ni), id_len: int ni,
   src: !$A.cborrow(l, n, cs), off: int o, len: int k): void

(* Opcode 19: a piece that is a literal of the program (a property name from
   css's table, ":" or ";") *)
#pub fun book_style_lit
  {lc:agz}{nc:pos | nc <= 64}{li:agz}{ni:pos | ni <= 1024}{m:nat | m <= 1024}
  (s: !book_stream, run: !book_style_run(lc, li),
   container: !$A.borrow(byte, lc, nc), container_len: int nc,
   id: !$A.borrow(byte, li, ni), id_len: int ni,
   lit: string m): void

(* Opcode 20: the style is whole *)
#pub fun book_style_end
  {lc:agz}{nc:pos | nc <= 64}{li:agz}{ni:pos | ni <= 1024}
  (s: !book_stream, run: book_style_run(lc, li),
   container: !$A.borrow(byte, lc, nc), container_len: int nc,
   id: !$A.borrow(byte, li, ni), id_len: int ni): void

(* A book's face from the bytes src[off, off + len) of an outside file: JS
   makes the family itself, book-<container id>-<face> (no name is taken from
   the caller), and adds it with new FontFace(family, bytes, descriptors) and
   document.fonts.add. No URL is made. A face number of 32 or more, a
   container that is not there and faces over 16 MiB in all are refused.
   weight is 1 to 1000 and style 0 normal, 1 italic, 2 oblique *)
#pub fun book_font_add
  {l:agz}{n:nat}{cs:$A.cells}{lc:agz}{nc:pos | nc <= 64}{o:nat}{k:pos | o + k <= n}
  (from: OUTSIDE_READ(cs) |
   src: !$A.cborrow(l, n, cs), off: int o, len: int k,
   container: !$A.borrow(byte, lc, nc), container_len: int nc,
   face: int, weight: int, style: int): void

(* The ordinary operations, written into the book stream in the format of the
   stream today (SET_TEXT 1, SET_ATTR 2, CREATE_ELEMENT 4, APPEND_TEXT 6,
   REMOVE_ATTR 7), so a book document can hold text, ordinary attributes and
   the app's own elements. Inside a container the flush refuses style and
   data-book-* (above) *)
#pub fun book_create_element
  {li:agz}{ni:pos | ni <= 1024}{lp:agz}{np:pos | np <= 1024}{lt:agz}{nt:pos | nt <= 255}
  (s: !book_stream, id: !$A.borrow(byte, li, ni), id_len: int ni,
   parent: !$A.borrow(byte, lp, np), parent_len: int np,
   tag: !$A.borrow(byte, lt, nt), tag_len: int nt): void

#pub fun book_set_text
  {li:agz}{ni:pos | ni <= 1024}{lt:agz}{nt:nat | nt <= 65535}
  (s: !book_stream, id: !$A.borrow(byte, li, ni), id_len: int ni,
   text: !$A.borrow(byte, lt, nt), text_len: int nt): void

#pub fun book_append_text
  {li:agz}{ni:pos | ni <= 1024}{lt:agz}{nt:nat | nt <= 65535}
  (s: !book_stream, id: !$A.borrow(byte, li, ni), id_len: int ni,
   text: !$A.borrow(byte, lt, nt), text_len: int nt): void

#pub fun book_set_attr
  {li:agz}{ni:pos | ni <= 1024}{ln:agz}{nn:pos | nn <= 255}{lv:agz}{nv:nat | nv <= 65535}
  (s: !book_stream, id: !$A.borrow(byte, li, ni), id_len: int ni,
   name: !$A.borrow(byte, ln, nn), name_len: int nn,
   value: !$A.borrow(byte, lv, nv), value_len: int nv): void

#pub fun book_remove_attr
  {li:agz}{ni:pos | ni <= 1024}{ln:agz}{nn:pos | nn <= 255}
  (s: !book_stream, id: !$A.borrow(byte, li, ni), id_len: int ni,
   name: !$A.borrow(byte, ln, nn), name_len: int nn): void

(* ============================================================
   Container ids, proved
   ============================================================ *)

dataprop BOOK_ID_START_CLASS(c: int, b: bool) =
  | {c:int} BOOK_ID_START_CLASS_yes(c, true) of BOOK_ID_START(c)
  | {c:int} BOOK_ID_START_CLASS_no(c, false)

fn _id_start_class {c:int | 0 <= c; c < 256} (c: int c): [b:bool] (BOOK_ID_START_CLASS(c, b) | bool b) =
  if c >= 97 then
    (if c <= 122 then (BOOK_ID_START_CLASS_yes(BOOK_ID_START_lower()) | true)
     else (BOOK_ID_START_CLASS_no() | false))
  else if c >= 65 then
    (if c <= 90 then (BOOK_ID_START_CLASS_yes(BOOK_ID_START_upper()) | true)
     else (BOOK_ID_START_CLASS_no() | false))
  else (BOOK_ID_START_CLASS_no() | false)

dataprop BOOK_ID_CLASS(c: int, b: bool) =
  | {c:int} BOOK_ID_CLASS_yes(c, true) of BOOK_ID_CH(c)
  | {c:int} BOOK_ID_CLASS_no(c, false)

fn _id_class {c:int | 0 <= c; c < 256} (c: int c): [b:bool] (BOOK_ID_CLASS(c, b) | bool b) =
  if c >= 97 then
    (if c <= 122 then (BOOK_ID_CLASS_yes(BOOK_ID_CH_start(BOOK_ID_START_lower())) | true)
     else (BOOK_ID_CLASS_no() | false))
  else if c >= 65 then
    (if c <= 90 then (BOOK_ID_CLASS_yes(BOOK_ID_CH_start(BOOK_ID_START_upper())) | true)
     else (BOOK_ID_CLASS_no() | false))
  else if c >= 48 then
    (if c <= 57 then (BOOK_ID_CLASS_yes(BOOK_ID_CH_digit()) | true) else (BOOK_ID_CLASS_no() | false))
  else if c = 45 then (BOOK_ID_CLASS_yes(BOOK_ID_CH_hyphen()) | true)
  else (BOOK_ID_CLASS_no() | false)

(* The bytes from 1 + k on, each checked *)
fun _id_rest {l:agz}{n:pos}{cs:$A.cells}{c:int}{k:nat | k + 1 <= n} .<n - k - 1>.
  (src: !$A.cborrow(l, n, cs), len: int n, k: int k,
   p0: $A.NTH(cs, 0, c), st: BOOK_ID_START(c), pf: BOOK_ID_REST(cs, 1, k))
  : [b:bool] (BOOK_ID_OPT(cs, n, b) | bool b) =
  if k + 1 >= len then (BOOK_ID_yes(BOOK_ID_mk(p0, st, pf)) | true)
  else let
    val @(pn | ch) = $A.cborrow_get(src, k + 1)
    val @(pc | b) = _id_class(ch)
  in
    if b then let
      prval BOOK_ID_CLASS_yes(chp) = pc
    in _id_rest(src, len, k + 1, p0, st, BOOK_ID_REST_snoc(pf, pn, chp)) end
    else let
      prval BOOK_ID_CLASS_no() = pc
    in (BOOK_ID_no() | false) end
  end

implement book_id_scan{l}{n}{cs}(src, len) = let
  val @(p0 | c) = $A.cborrow_get(src, 0)
  val @(pc | b) = _id_start_class(c)
in
  if b then let
    prval BOOK_ID_START_CLASS_yes(st) = pc
  in _id_rest(src, len, 0, p0, st, BOOK_ID_REST_nil()) end
  else let
    prval BOOK_ID_START_CLASS_no() = pc
  in (BOOK_ID_no() | false) end
end

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

$UNSAFE begin
%{
extern void bats_dom_flush_book(void*, int);
extern void bats_js_book_font_add(void*, int, int, void*, int, int, int, int);
extern void *bats_book_stream_new(void);
extern void bats_book_stream_free(void*);
extern void bats_book_flush(void*);
extern void bats_book_reserve(void*, int);
extern void bats_book_u8(void*, int);
extern void bats_book_u16(void*, int);
extern void bats_book_bytes(void*, void*, int, int);
%}
%{$
/* The book stream: operations whole in a buffer of 131072 bytes. An encoder
   reserves room for all of its operation first (flushing what is there when
   it does not fit) and then writes, so a flush never falls inside one; the
   largest operation is under 80000 bytes (a 65535-byte piece and three ids
   of at most 1024). The caller's types bound every length */
#define BATS_BOOK_CAP 131072
typedef struct { int len; unsigned char buf[BATS_BOOK_CAP]; } bats_book_stream;

void *bats_book_stream_new(void) {
  bats_book_stream *s = (bats_book_stream *)malloc(sizeof(bats_book_stream));
  s->len = 0;
  return s;
}

void bats_book_stream_free(void *p) { free(p); }

void bats_book_flush(void *p) {
  bats_book_stream *s = (bats_book_stream *)p;
  int n = s->len;
  if (n > 0) { s->len = 0; bats_dom_flush_book(s->buf, n); }
}

void bats_book_reserve(void *p, int need) {
  bats_book_stream *s = (bats_book_stream *)p;
  if (s->len + need > BATS_BOOK_CAP) bats_book_flush(p);
}

void bats_book_u8(void *p, int v) {
  bats_book_stream *s = (bats_book_stream *)p;
  s->buf[s->len++] = (unsigned char)v;
}

void bats_book_u16(void *p, int v) {
  bats_book_u8(p, v & 255);
  bats_book_u8(p, (v >> 8) & 255);
}

void bats_book_bytes(void *p, void *src, int off, int n) {
  bats_book_stream *s = (bats_book_stream *)p;
  memcpy(s->buf + s->len, (unsigned char *)src + off, n);
  s->len += n;
}
%}
extern fun _book_new (): ptr = "mac#bats_book_stream_new"
extern fun _book_free (p: ptr): void = "mac#bats_book_stream_free"
extern fun _book_flush (p: ptr): void = "mac#bats_book_flush"
extern fun _book_reserve (p: ptr, need: int): void = "mac#bats_book_reserve"
extern fun _book_u8 (p: ptr, v: int): void = "mac#bats_book_u8"
extern fun _book_u16 (p: ptr, v: int): void = "mac#bats_book_u16"
extern fun _book_bytes (p: ptr, src: ptr, off: int, n: int): void = "mac#bats_book_bytes"
extern fun _book_font_add
  (src: ptr, off: int, len: int, container: ptr, container_len: int, face: int, weight: int, style: int)
  : void = "mac#bats_js_book_font_add"

assume book_stream = ptr
end

implement book_stream_new () = _book_new()

implement book_stream_free (s) = _book_free(s)

implement dom_flush_book (s) = _book_flush(s)

(* An id or a name as the stream writes it: its length (u16, little endian),
   then its bytes *)
fn _put_name {l:agz}{n:nat} (s: !book_stream, b: !$A.borrow(byte, l, n), len: int n): void = let
  val () = _book_u16(s, len)
in _book_bytes(s, $UNSAFE begin $UNSAFE.castvwtp1{ptr}(b) end, 0, len) end

(* A span of outside bytes as the stream writes it, after its length *)
fn _put_span {l:agz}{n:nat}{cs:$A.cells}{o,k:nat | o + k <= n}
  (s: !book_stream, src: !$A.cborrow(l, n, cs), off: int o, len: int k): void =
  _book_bytes(s, $UNSAFE begin $UNSAFE.castvwtp1{ptr}(src) end, off, len)

(* A literal of the program as the stream writes it, after its length *)
fn _put_lit {m:nat} (s: !book_stream, lit: string m, n: int m): void =
  _book_bytes(s, $UNSAFE begin $UNSAFE.cast{ptr}(lit) end, 0, n)

implement book_container{l}{n}{cs}{lc}{nc}{csc}{lp}{np}{g}(pf, pid | s, doc, id, id_len, parent, parent_len, layout) = let
  val () = _book_reserve(s, 8192)
  val () = _book_u8(s, 13)
  val () = _book_u16(s, id_len)
  val () = _book_bytes(s, $UNSAFE begin $UNSAFE.castvwtp1{ptr}(id) end, 0, id_len)
  val () = _put_name(s, parent, parent_len)
in _book_u8(s, layout) end

implement book_element{l}{n}{cs}{lc}{nc}{li}{ni}{lp}{np}{lt}{nt}{o,k}
  (pf | s, container, container_len, id, id_len, parent, parent_len, tag, tag_len, src, name_off, name_len) = let
  val () = _book_reserve(s, 8192)
  val () = _book_u8(s, 14)
  val () = _put_name(s, container, container_len)
  val () = _put_name(s, id, id_len)
  val () = _put_name(s, parent, parent_len)
  val () = _book_u8(s, tag_len)
  val () = _book_bytes(s, $UNSAFE begin $UNSAFE.castvwtp1{ptr}(tag) end, 0, tag_len)
  val () = _book_u8(s, name_len)
in _put_span(s, src, name_off, name_len) end

implement book_style{l}{n}{cs}{lc}{nc}{li}{ni}{o,k}
  (pf | s, container, container_len, id, id_len, src, off, len) = let
  val () = _book_reserve(s, 8192 + len)
  val () = _book_u8(s, 15)
  val () = _put_name(s, container, container_len)
  val () = _put_name(s, id, id_len)
  val () = _book_u16(s, len)
in _put_span(s, src, off, len) end

implement book_names{l}{n}{cs}{lc}{nc}{li}{ni}{kind}{o,k}
  (pf | s, container, container_len, id, id_len, kind, src, off, len) = let
  val () = _book_reserve(s, 8192 + len)
  val () = _book_u8(s, 16)
  val () = _put_name(s, container, container_len)
  val () = _put_name(s, id, id_len)
  val () = _book_u8(s, kind)
  val () = _book_u16(s, len)
in _put_span(s, src, off, len) end

implement book_sheet_span{l}{n}{cs}{lc}{nc}{o,k}
  (pf | s, container, container_len, src, off, len) = let
  val () = _book_reserve(s, 8192 + len)
  val () = _book_u8(s, 17)
  val () = _put_name(s, container, container_len)
  val () = _book_u16(s, len)
in _put_span(s, src, off, len) end

implement book_sheet_lit{lc}{nc}{m}(s, container, container_len, lit) = let
  val n = g1u2i(string1_length(lit))
  val () = _book_reserve(s, 8192 + n)
  val () = _book_u8(s, 17)
  val () = _put_name(s, container, container_len)
  val () = _book_u16(s, n)
in _put_lit(s, lit, n) end

implement book_style_begin{lc}{nc}{li}{ni}(container, id) = book_style_run_mk()

implement book_style_span{l}{n}{cs}{lc}{nc}{li}{ni}{o,k}
  (pf | s, run, container, container_len, id, id_len, src, off, len) = let
  val () = _book_reserve(s, 8192 + len)
  val () = _book_u8(s, 19)
  val () = _put_name(s, container, container_len)
  val () = _put_name(s, id, id_len)
  val () = _book_u16(s, len)
in _put_span(s, src, off, len) end

implement book_style_lit{lc}{nc}{li}{ni}{m}(s, run, container, container_len, id, id_len, lit) = let
  val n = g1u2i(string1_length(lit))
  val () = _book_reserve(s, 8192 + n)
  val () = _book_u8(s, 19)
  val () = _put_name(s, container, container_len)
  val () = _put_name(s, id, id_len)
  val () = _book_u16(s, n)
in _put_lit(s, lit, n) end

implement book_style_end{lc}{nc}{li}{ni}(s, run, container, container_len, id, id_len) = let
  val ~book_style_run_mk() = run
  val () = _book_reserve(s, 8192)
  val () = _book_u8(s, 20)
  val () = _put_name(s, container, container_len)
in _put_name(s, id, id_len) end

implement book_sheet_id{lc}{nc}(s, container, container_len) = let
  val () = _book_reserve(s, 8192)
  val () = _book_u8(s, 17)
  val () = _put_name(s, container, container_len)
in _put_name(s, container, container_len) end

implement book_sheet_end{lc}{nc}(s, container, container_len) = let
  val () = _book_reserve(s, 8192)
  val () = _book_u8(s, 18)
in _put_name(s, container, container_len) end

implement book_font_add{l}{n}{cs}{lc}{nc}{o}{k}
  (pf | src, off, len, container, container_len, face, weight, style) =
  _book_font_add($UNSAFE begin $UNSAFE.castvwtp1{ptr}(src) end, off, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(container) end, container_len, face, weight, style)

implement book_create_element{li}{ni}{lp}{np}{lt}{nt}(s, id, id_len, parent, parent_len, tag, tag_len) = let
  val () = _book_reserve(s, 8192)
  val () = _book_u8(s, 4)
  val () = _put_name(s, id, id_len)
  val () = _put_name(s, parent, parent_len)
  val () = _book_u8(s, tag_len)
in _book_bytes(s, $UNSAFE begin $UNSAFE.castvwtp1{ptr}(tag) end, 0, tag_len) end

implement book_set_text{li}{ni}{lt}{nt}(s, id, id_len, text, text_len) = let
  val () = _book_reserve(s, 8192 + text_len)
  val () = _book_u8(s, 1)
  val () = _put_name(s, id, id_len)
  val () = _book_u16(s, text_len)
in _book_bytes(s, $UNSAFE begin $UNSAFE.castvwtp1{ptr}(text) end, 0, text_len) end

implement book_append_text{li}{ni}{lt}{nt}(s, id, id_len, text, text_len) = let
  val () = _book_reserve(s, 8192 + text_len)
  val () = _book_u8(s, 6)
  val () = _put_name(s, id, id_len)
  val () = _book_u16(s, text_len)
in _book_bytes(s, $UNSAFE begin $UNSAFE.castvwtp1{ptr}(text) end, 0, text_len) end

implement book_set_attr{li}{ni}{ln}{nn}{lv}{nv}(s, id, id_len, name, name_len, value, value_len) = let
  val () = _book_reserve(s, 8192 + value_len)
  val () = _book_u8(s, 2)
  val () = _put_name(s, id, id_len)
  val () = _book_u8(s, name_len)
  val () = _book_bytes(s, $UNSAFE begin $UNSAFE.castvwtp1{ptr}(name) end, 0, name_len)
  val () = _book_u16(s, value_len)
in _book_bytes(s, $UNSAFE begin $UNSAFE.castvwtp1{ptr}(value) end, 0, value_len) end

implement book_remove_attr{li}{ni}{ln}{nn}(s, id, id_len, name, name_len) = let
  val () = _book_reserve(s, 8192)
  val () = _book_u8(s, 7)
  val () = _put_name(s, id, id_len)
  val () = _book_u8(s, name_len)
in _book_bytes(s, $UNSAFE begin $UNSAFE.castvwtp1{ptr}(name) end, 0, name_len) end

end (* #target wasm *)
