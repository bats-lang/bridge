#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use wasm.bats-packages.dev/bridge as B
staload OU = "wasm.bats-packages.dev/bridge/src/outside.bats"
staload BC = "wasm.bats-packages.dev/bridge/src/book_content.bats"
staload DM = "wasm.bats-packages.dev/bridge/src/dom.bats"
staload WI = "wasm.bats-packages.dev/bridge/src/window.bats"

(* Book content through bridge's encoders (book_content.bats), played over the
   bytes of an outside file that check.mjs picks: its lines are the document,
   the declarations, the sheets and the face the cases use (line k of the file
   is the k-th below). Each case ends with a log line "@snap <name>", where
   check.mjs reads the document. *)

(* s's bytes in a fresh array of exactly its length *)
fn exact {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

(* s as a borrow, to be let go with rel *)
fn lit {n:pos | n < 256} (s: string n): [l:agz] @($A.frozen(byte, l, n, 1), $A.borrow(byte, l, n)) =
  $A.freeze<byte>(exact(s))

fn rel {l:agz}{n:nat} (fz: $A.frozen(byte, l, n, 1), b: $A.borrow(byte, l, n)): void = let
  val () = $A.drop<byte>(fz, b)
in $A.free<byte>($A.thaw<byte>(fz)) end

fn say {n:pos | n < 256} (line: string n): void = let
  val @(fz, b) = lit(line)
  val () = $WI.log($WI.Info(), b, g1u2i(string1_length(line)))
in rel(fz, b) end

(* The end of the line that starts at p: the next line feed, or n *)
fun end_of_line {l:agz}{n:nat}{cs:$A.cells}{p:nat | p <= n} .<n - p>.
  (cb: !$A.cborrow(l, n, cs), n: int n, p: int p): [q:nat | p <= q; q <= n] int q =
  if p >= n then p
  else let
    val @(pf | c) = $A.cborrow_get(cb, p)
  in if c = 10 then p else end_of_line(cb, n, p + 1) end

(* Line number want, from p on, as its offset and length (an empty one when
   there is none) *)
fun line_at {l:agz}{n:nat}{cs:$A.cells}{p:nat | p <= n} .<n - p>.
  (cb: !$A.cborrow(l, n, cs), n: int n, p: int p, want: int): [o,k:nat | o + k <= n] @(int o, int k) = let
  val q = end_of_line(cb, n, p)
in
  if want <= 0 then @(p, q - p)
  else if q >= n then @(n, 0)
  else line_at(cb, n, q + 1, want - 1)
end

(* A container, with its id proved first *)
fn container {l:agz}{n:nat}{cs:$A.cells}{nc:pos | nc < 64}{np:pos | np < 64}
  (pf: $OU.OUTSIDE_READ(cs) | s: !$BC.book_stream, doc: !$A.cborrow(l, n, cs),
   cid: string nc, parent: string np, layout: int 1): void = let
  val @(pfl | idb) = $A.barr_of_arr(exact(cid))
  val @(idz, idc) = $A.barr_freeze(idb)
  val ncl = g1u2i(string1_length(cid))
  val @(r | ok) = $BC.book_id_scan(idc, ncl)
  val () = (if ok then let
      prval $BC.BOOK_ID_yes(pid) = r
      val @(pz, pb) = lit(parent)
      val () = $BC.book_container(pf, pid | s, doc, idc, ncl, pb, g1u2i(string1_length(parent)), 1)
    in rel(pz, pb) end
    else let
      prval $BC.BOOK_ID_no() = r
    in say("id refused by the proof") end)
  val () = $A.cborrow_drop(idz, idc)
in $A.free<byte>($A.barr_to_arr($A.barr_thaw(idz))) end

fn element {l:agz}{n:nat}{cs:$A.cells}{nc,ni,np,nt:pos | nc < 64; ni < 64; np < 64; nt < 64}{o,k:nat | o + k <= n; k <= 255}
  (pf: $OU.OUTSIDE_READ(cs) | s: !$BC.book_stream, doc: !$A.cborrow(l, n, cs),
   c: string nc, id: string ni, parent: string np, tag: string nt, name_off: int o, name_len: int k): void = let
  val @(cz, cb) = lit(c)
  val @(iz, ib) = lit(id)
  val @(pz, pb) = lit(parent)
  val @(tz, tb) = lit(tag)
  val () = $BC.book_element(pf | s, cb, g1u2i(string1_length(c)), ib, g1u2i(string1_length(id)),
    pb, g1u2i(string1_length(parent)), tb, g1u2i(string1_length(tag)), doc, name_off, name_len)
  val () = rel(tz, tb)
  val () = rel(pz, pb)
  val () = rel(iz, ib)
in rel(cz, cb) end

(* The element made as the name on line ln of the file *)
fn element_named {l:agz}{n:nat}{cs:$A.cells}{nc,ni,np,nt:pos | nc < 64; ni < 64; np < 64; nt < 64}
  (pf: $OU.OUTSIDE_READ(cs) | s: !$BC.book_stream, doc: !$A.cborrow(l, n, cs), n: int n,
   c: string nc, id: string ni, parent: string np, tag: string nt, ln: int): void = let
  val @(o, k) = line_at(doc, n, 0, ln)
in if k <= 255 then element(pf | s, doc, c, id, parent, tag, o, k) else () end

(* The declarations on line ln as the style of a book element *)
fn style {l:agz}{n:nat}{cs:$A.cells}{nc,ni:pos | nc < 64; ni < 64}
  (pf: $OU.OUTSIDE_READ(cs) | s: !$BC.book_stream, doc: !$A.cborrow(l, n, cs), n: int n,
   c: string nc, id: string ni, ln: int): void = let
  val @(o, k) = line_at(doc, n, 0, ln)
  val @(cz, cb) = lit(c)
  val @(iz, ib) = lit(id)
  val () = (if k <= 65535 then
    $BC.book_style(pf | s, cb, g1u2i(string1_length(c)), ib, g1u2i(string1_length(id)), doc, o, k)
    else ())
  val () = rel(iz, ib)
in rel(cz, cb) end

fn names {l:agz}{n:nat}{cs:$A.cells}{nc,ni:pos | nc < 64; ni < 64}
  (pf: $OU.OUTSIDE_READ(cs) | s: !$BC.book_stream, doc: !$A.cborrow(l, n, cs), n: int n,
   c: string nc, id: string ni, kind: int, ln: int): void = let
  val @(o, k) = line_at(doc, n, 0, ln)
  val @(cz, cb) = lit(c)
  val @(iz, ib) = lit(id)
  val () = (if k <= 65535 then
    (if kind = 1 then $BC.book_names(pf | s, cb, g1u2i(string1_length(c)), ib, g1u2i(string1_length(id)), 1, doc, o, k)
     else if kind = 2 then $BC.book_names(pf | s, cb, g1u2i(string1_length(c)), ib, g1u2i(string1_length(id)), 2, doc, o, k)
     else $BC.book_names(pf | s, cb, g1u2i(string1_length(c)), ib, g1u2i(string1_length(id)), 3, doc, o, k))
    else ())
  val () = rel(iz, ib)
in rel(cz, cb) end

(* A piece of a sheet: line ln of the file, whole *)
fn piece {l:agz}{n:nat}{cs:$A.cells}{nc:pos | nc < 64}
  (pf: $OU.OUTSIDE_READ(cs) | s: !$BC.book_stream, doc: !$A.cborrow(l, n, cs), n: int n,
   c: string nc, ln: int): void = let
  val @(o, k) = line_at(doc, n, 0, ln)
  val @(cz, cb) = lit(c)
  val () = (if k <= 65535 then
    $BC.book_sheet_span(pf | s, cb, g1u2i(string1_length(c)), doc, o, k) else ())
in rel(cz, cb) end

fn piece_lit {nc:pos | nc < 64}{m:nat | m <= 1024}
  (s: !$BC.book_stream, c: string nc, text: string m): void = let
  val @(cz, cb) = lit(c)
  val () = $BC.book_sheet_lit(s, cb, g1u2i(string1_length(c)), text)
in rel(cz, cb) end

(* The sheet [data-book-container="<id>"] h2{margin:0}, the id written by
   book_sheet_id, split in two pieces: up to the id, and after it *)
fn piece_id_open {nc:pos | nc < 64} (s: !$BC.book_stream, c: string nc): void = let
  val @(cz, cb) = lit(c)
  val () = $BC.book_sheet_lit(s, cb, g1u2i(string1_length(c)), "[data-book-container=\"")
  val () = $BC.book_sheet_id(s, cb, g1u2i(string1_length(c)))
in rel(cz, cb) end

fn piece_id_close {nc:pos | nc < 64} (s: !$BC.book_stream, c: string nc): void = let
  val @(cz, cb) = lit(c)
  val () = $BC.book_sheet_lit(s, cb, g1u2i(string1_length(c)), "\"] h2{margin:0}")
  val () = $BC.book_sheet_end(s, cb, g1u2i(string1_length(c)))
in rel(cz, cb) end

fn sheet_end {nc:pos | nc < 64} (s: !$BC.book_stream, c: string nc): void = let
  val @(cz, cb) = lit(c)
  val () = $BC.book_sheet_end(s, cb, g1u2i(string1_length(c)))
in rel(cz, cb) end

(* A whole sheet: lines ln of the file as one piece, then the end *)
fn sheet {l:agz}{n:nat}{cs:$A.cells}{nc:pos | nc < 64}
  (pf: $OU.OUTSIDE_READ(cs) | s: !$BC.book_stream, doc: !$A.cborrow(l, n, cs), n: int n,
   c: string nc, ln: int): void = let
  val () = piece(pf | s, doc, n, c, ln)
in sheet_end(s, c) end

(* An app element in a container: the ordinary operations, written into the
   book stream *)
fn app_element {ni,np:pos | ni < 64; np < 64}
  (s: !$BC.book_stream, id: string ni, parent: string np): void = let
  val @(iz, ib) = lit(id)
  val @(pz, pb) = lit(parent)
  val @(tz, tb) = lit("span")
  val () = $BC.book_create_element(s, ib, g1u2i(string1_length(id)), pb, g1u2i(string1_length(parent)), tb, 4)
  val () = rel(tz, tb)
  val () = rel(pz, pb)
in rel(iz, ib) end

fn app_attr {ni,nn,nv:pos | ni < 64; nn < 64; nv < 64}
  (s: !$BC.book_stream, id: string ni, name: string nn, value: string nv): void = let
  val @(iz, ib) = lit(id)
  val @(nz, nb) = lit(name)
  val @(vz, vb) = lit(value)
  val () = $BC.book_set_attr(s, ib, g1u2i(string1_length(id)), nb, g1u2i(string1_length(name)),
    vb, g1u2i(string1_length(value)))
  val () = rel(vz, vb)
  val () = rel(nz, nb)
in rel(iz, ib) end

fn app_unattr {ni,nn:pos | ni < 64; nn < 64}
  (s: !$BC.book_stream, id: string ni, name: string nn): void = let
  val @(iz, ib) = lit(id)
  val @(nz, nb) = lit(name)
  val () = $BC.book_remove_attr(s, ib, g1u2i(string1_length(id)), nb, g1u2i(string1_length(name)))
  val () = rel(nz, nb)
in rel(iz, ib) end

(* The same operations through the ordinary stream, as bytes: dom_flush *)
#define CAP 512

fn put_name {l:agz}{o:nat}{n:pos | n < 256; o + 2 + n <= CAP}
  (buf: !$A.arr(byte, l, CAP), off: int o, s: string n): int(o + 2 + n) = let
  val n = g1u2i(string1_length(s))
  val () = $A.set<byte>(buf, off, $A.int2byte(n))
  val () = $A.set<byte>(buf, off + 1, $A.int2byte(0))
  val () = $A.write_text(buf, off + 2, $A.text_lit(s), n)
in off + 2 + n end

fn put_byte {l:agz}{o:nat | o + 1 <= CAP}{v:nat | v < 256}
  (buf: !$A.arr(byte, l, CAP), off: int o, v: int v): int(o + 1) = let
  val () = $A.set<byte>(buf, off, $A.int2byte(v))
in off + 1 end

(* SET_ATTR or REMOVE_ATTR of one attribute, and a REMOVE_CHILD, a CLONE_NODE
   and a raw opcode 13, in a flush of their own *)
fn raw_set_attr {ni,nn,nv:pos | ni < 40; nn < 40; nv < 40} (id: string ni, name: string nn, value: string nv): void = let
  val buf = $A.alloc<byte>(CAP)
  val off = put_byte(buf, 0, 2)
  val off = put_name(buf, off, id)
  val n = g1u2i(string1_length(name))
  val off = put_byte(buf, off, 5)
  val () = $A.write_text(buf, off, $A.text_lit(name), n)
  val off = off + 5
  val off = put_name(buf, off, value)
  val () = $DM.dom_flush(buf, off)
in $A.free<byte>(buf) end

fn raw_clone {ni,ns,np:pos | ni < 40; ns < 40; np < 40} (id: string ni, source: string ns, parent: string np): void = let
  val buf = $A.alloc<byte>(CAP)
  val off = put_byte(buf, 0, 8)
  val off = put_name(buf, off, id)
  val off = put_name(buf, off, source)
  val off = put_name(buf, off, parent)
  val () = $DM.dom_flush(buf, off)
in $A.free<byte>(buf) end

fn raw_remove {ni:pos | ni < 40} (id: string ni): void = let
  val buf = $A.alloc<byte>(CAP)
  val off = put_byte(buf, 0, 5)
  val off = put_name(buf, off, id)
  val () = $DM.dom_flush(buf, off)
in $A.free<byte>(buf) end

fn raw_container {ni,np:pos | ni < 40; np < 40} (id: string ni, parent: string np): void = let
  val buf = $A.alloc<byte>(CAP)
  val off = put_byte(buf, 0, 13)
  val off = put_name(buf, off, id)
  val off = put_name(buf, off, parent)
  val off = put_byte(buf, off, 1)
  val () = $DM.dom_flush(buf, off)
in $A.free<byte>(buf) end

(* A face from the bytes on line ln of the file *)
fn face {l:agz}{n:nat}{cs:$A.cells}{nc:pos | nc < 64}
  (pf: $OU.OUTSIDE_READ(cs) | doc: !$A.cborrow(l, n, cs), n: int n, c: string nc, ln: int, number: int): void = let
  val @(o, k) = line_at(doc, n, 0, ln)
  val @(cz, cb) = lit(c)
  val () = (if k > 0 then
    $BC.book_font_add(pf | doc, o, k, cb, g1u2i(string1_length(c)), number, 400, 0) else ())
in rel(cz, cb) end

(* Everything, over the file's bytes *)
fn play {l:agz}{n:nat}{cs:$A.cells}
  (pf: $OU.OUTSIDE_READ(cs) | s: !$BC.book_stream, doc: !$A.cborrow(l, n, cs), n: int n): void = let
  (* book-container-id: an id the proof refuses, an id it takes, and then the
     same id again, a missing parent, and a container inside a container *)
  val () = container(pf | s, doc, "1bad", "stage", 1)
  val () = container(pf | s, doc, "chap", "stage", 1)
  val () = $BC.dom_flush_book(s)
  val () = container(pf | s, doc, "chap", "stage", 1)
  val () = container(pf | s, doc, "orphan", "missing", 1)
  val () = $BC.dom_flush_book(s)
  val () = say("@snap book-container-id")
  (* book-container: elements, the app's own element inside, the writes the
     ordinary operations may not make, the parents a book element may not
     have, a clone, and the removal that drops the sheets *)
  val () = element_named(pf | s, doc, n, "chap", "c1", "chap", "p", 1)
  val () = element_named(pf | s, doc, n, "chap", "c2", "c1", "em", 1)
  val () = element_named(pf | s, doc, n, "chap", "c3", "stage", "p", 1)
  val () = element_named(pf | s, doc, n, "chap", "c4", "chap", "button", 1)
  val () = element_named(pf | s, doc, n, "chap", "c5", "chap", "script", 1)
  val () = style(pf | s, doc, n, "chap", "c1", 2)
  val () = style(pf | s, doc, n, "chap", "stage", 2)
  val () = names(pf | s, doc, n, "chap", "c1", 1, 4)
  val () = app_element(s, "app1", "c1")
  val () = app_attr(s, "app1", "title", "mine")
  val () = app_attr(s, "app1", "style", "color:red")
  val () = app_attr(s, "c1", "style", "color:blue")
  val () = app_attr(s, "c1", "data-book-class", "forged")
  val () = app_attr(s, "stage", "data-book-element", "forged")
  val () = app_unattr(s, "c1", "data-book-element")
  val () = container(pf | s, doc, "inner", "c1", 1)
  val () = container(pf | s, doc, "other", "stage", 1)
  val () = element_named(pf | s, doc, n, "chap", "c6", "other", "p", 1)
  val () = element_named(pf | s, doc, n, "chap", "c7", "chap", "p", 65)
  val () = element_named(pf | s, doc, n, "chap", "c8", "chap", "p", 66)
  val () = element_named(pf | s, doc, n, "chap", "c9", "chap", "p", 67)
  val () = names(pf | s, doc, n, "chap", "c1", 1, 59)
  val () = names(pf | s, doc, n, "chap", "c1", 1, 60)
  val () = names(pf | s, doc, n, "chap", "c1", 1, 61)
  val () = names(pf | s, doc, n, "chap", "c1", 1, 62)
  val () = names(pf | s, doc, n, "chap", "c1", 1, 63)
  val () = names(pf | s, doc, n, "chap", "c1", 1, 64)
  val () = element_named(pf | s, doc, n, "other", "o1", "other", "p", 1)
  val () = sheet(pf | s, doc, n, "chap", 5)
  val () = app_attr(s, "chap", "style", "width: 5px")
  val () = $BC.dom_flush_book(s)
  val () = raw_set_attr("c1", "style", "color:green")
  val () = raw_set_attr("stage", "data-book-id", "forged")
  val () = raw_set_attr("chap", "style", "height: 7px")
  val () = raw_clone("clone1", "c1", "stage")
  val () = raw_clone("clone2", "c1", "chap")
  val () = raw_container("rawbook", "stage")
  val () = say("@snap book-container")
  val () = raw_remove("other")
  val () = say("@snap book-container-removed")
  (* book-sheet: a sheet in two pieces across two flushes, and the refusals *)
  val () = piece(pf | s, doc, n, "chap", 22)
  val () = $BC.dom_flush_book(s)
  val () = piece(pf | s, doc, n, "chap", 23)
  val () = sheet_end(s, "chap")
  val () = piece_lit(s, "chap", "[data-book-container=\"chap\"] h1{margin:0}")
  val () = sheet_end(s, "chap")
  val () = sheet(pf | s, doc, n, "chap", 7)
  val () = sheet(pf | s, doc, n, "chap", 8)
  val () = sheet(pf | s, doc, n, "chap", 9)
  val () = sheet(pf | s, doc, n, "chap", 10)
  val () = sheet(pf | s, doc, n, "chap", 11)
  val () = sheet(pf | s, doc, n, "chap", 12)
  val () = sheet(pf | s, doc, n, "chap", 13)
  val () = sheet(pf | s, doc, n, "chap", 24)
  val () = sheet(pf | s, doc, n, "chap", 25)
  val () = sheet(pf | s, doc, n, "chap", 27)
  val () = style(pf | s, doc, n, "chap", "c1", 3)
  val () = sheet(pf | s, doc, n, "chap", 28)
  val () = sheet(pf | s, doc, n, "chap", 29)
  val () = sheet(pf | s, doc, n, "chap", 30)
  val () = sheet(pf | s, doc, n, "chap", 31)
  val () = sheet(pf | s, doc, n, "chap", 32)
  val () = sheet(pf | s, doc, n, "chap", 33)
  val () = sheet(pf | s, doc, n, "chap", 34)
  val () = sheet(pf | s, doc, n, "chap", 35)
  val () = sheet(pf | s, doc, n, "chap", 36)
  val () = sheet(pf | s, doc, n, "chap", 37)
  val () = sheet(pf | s, doc, n, "chap", 38)
  val () = sheet(pf | s, doc, n, "chap", 39)
  val () = sheet(pf | s, doc, n, "chap", 40)
  val () = style(pf | s, doc, n, "chap", "c1", 41)
  val () = style(pf | s, doc, n, "chap", "c1", 42)
  val () = style(pf | s, doc, n, "chap", "c1", 43)
  val () = style(pf | s, doc, n, "chap", "c1", 44)
  val () = style(pf | s, doc, n, "chap", "c1", 45)
  val () = style(pf | s, doc, n, "chap", "c1", 46)
  val () = style(pf | s, doc, n, "chap", "c1", 47)
  val () = style(pf | s, doc, n, "chap", "c1", 48)
  val () = style(pf | s, doc, n, "chap", "c1", 49)
  val () = style(pf | s, doc, n, "chap", "c1", 50)
  val () = style(pf | s, doc, n, "chap", "c1", 51)
  val () = style(pf | s, doc, n, "chap", "c1", 52)
  val () = style(pf | s, doc, n, "chap", "c1", 53)
  val () = style(pf | s, doc, n, "chap", "c1", 54)
  val () = style(pf | s, doc, n, "chap", "c1", 55)
  val () = style(pf | s, doc, n, "chap", "c1", 56)
  val () = style(pf | s, doc, n, "chap", "c1", 57)
  val () = style(pf | s, doc, n, "chap", "c1", 58)
  val () = $BC.dom_flush_book(s)
  val () = say("@snap book-sheet")
  (* book-sheet-at-rule, book-sheet-comment *)
  val () = sheet(pf | s, doc, n, "chap", 6)
  val () = sheet(pf | s, doc, n, "chap", 14)
  val () = sheet(pf | s, doc, n, "chap", 15)
  val () = sheet(pf | s, doc, n, "chap", 16)
  val () = sheet(pf | s, doc, n, "chap", 17)
  val () = sheet(pf | s, doc, n, "chap", 18)
  val () = sheet(pf | s, doc, n, "chap", 19)
  val () = sheet(pf | s, doc, n, "chap", 20)
  val () = $BC.dom_flush_book(s)
  val () = say("@snap book-sheet-at-rule")
  val () = sheet(pf | s, doc, n, "chap", 21)
  val () = $BC.dom_flush_book(s)
  val () = say("@snap book-sheet-comment")
  (* book-font, book-font-name *)
  val () = face(pf | doc, n, "chap", 26, 0)
  val () = face(pf | doc, n, "chap", 26, 1)
  val () = face(pf | doc, n, "chap", 26, 1)
  val () = face(pf | doc, n, "chap", 26, 32)
  val () = face(pf | doc, n, "nowhere", 26, 2)
  val () = say("@snap book-font")
  val () = say("@snap book-font-name")
  (* book-sheet-id: the container's id written by book_sheet_id, in two pieces
     across a flush, beside the literal pieces *)
  val () = piece_id_open(s, "chap")
  val () = $BC.dom_flush_book(s)
  val () = piece_id_close(s, "chap")
  val () = $BC.dom_flush_book(s)
  val () = say("@snap book-sheet-id")
  val () = raw_remove("chap")
  val () = say("@snap book-removed")
in end

(* The file's bytes, read whole *)
fn read_and_play {n:pos | n <= 1048576} (f: !$OU.infile_outside(n), n: int n): void = let
  val a = $A.alloc<byte>(n)
  val @(pfo, pfc, pflent | ba) = $OU.file_read_outside(f, 0, a, n)
  val @(fz, cb) = $A.barr_freeze(ba)
  val s = $BC.book_stream_new()
  val () = play(pfo | s, cb, n)
  val () = $BC.dom_flush_book(s)
  val () = $BC.book_stream_free(s)
  val () = $A.cborrow_drop(fz, cb)
  val back = $A.barr_to_arrx(pflent | $A.barr_thaw(fz))
in $A.free<byte>(back) end

fn handle {m:nat} (f: $OU.infile_outside(m)): void = let
  val n = $OU.file_size_outside(f)
  val () = (if n > 0 then (if n <= 1048576 then read_and_play(f, n) else say("big")) else say("empty"))
in $OU.file_close_outside(f) end

implement main0 () = let
  val @(iz, ib) = lit("script")
  val opened = $OU.file_open_at_outside(ib, 6, 0)
  val () = rel(iz, ib)
in $P.finish<$OU.opened_outside>(opened, llam (got) =>
  case+ got of
  | ~$OU.OpenedOutside(f) => handle(f)
  | ~$OU.NotOpenedOutside() => say("not opened")
  | ~$OU.OpenFailedOutside() => say("open failed")) end
