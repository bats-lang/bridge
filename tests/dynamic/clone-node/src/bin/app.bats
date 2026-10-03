#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload DM = "wasm.bats-packages.dev/bridge/src/dom.bats"

#define CAP 256

(* s at off as the stream writes a name: its length (u16, little
   endian), then its bytes; the offset after it *)
fn put_name {l:agz}{o:nat}{n:pos | n < 256; o + 2 + n <= CAP}
  (buf: !$A.arr(byte, l, CAP), off: int o, s: string n): int(o + 2 + n) = let
  val n = g1u2i(string1_length(s))
  val () = $A.set<byte>(buf, off, $A.int2byte(n))
  val () = $A.set<byte>(buf, off + 1, $A.int2byte(0))
  val () = $A.write_text(buf, off + 2, $A.text_lit(s), n)
in off + 2 + n end

(* One byte at off; the offset after it *)
fn put_byte {l:agz}{o:nat | o + 1 <= CAP}{v:nat | v < 256}
  (buf: !$A.arr(byte, l, CAP), off: int o, v: int v): int(o + 1) = let
  val () = $A.set<byte>(buf, off, $A.int2byte(v))
in off + 1 end

(* low + 256 * high at off, as an i32, little endian; the offset after
   it *)
fn put_i32 {l:agz}{o:nat | o + 4 <= CAP}{low,high:nat | low < 256; high < 256}
  (buf: !$A.arr(byte, l, CAP), off: int o, low: int low, high: int high): int(o + 4) = let
  val () = $A.set<byte>(buf, off, $A.int2byte(low))
  val () = $A.set<byte>(buf, off + 1, $A.int2byte(high))
  val () = $A.set<byte>(buf, off + 2, $A.int2byte(0))
  val () = $A.set<byte>(buf, off + 3, $A.int2byte(0))
in off + 4 end

(* Through dom_flush, in one flush: element "page" (check.mjs made it,
   with markup the stream would refuse) given a title, then cloned into
   "sheet" as "copy" (with the title: in order), and again as "again";
   then the copy's tabindex removed, inert set and its scroll set, one
   axis per operation, as any element's; scrolls of an element that is
   not there and a clone of one, and a clone of a form (an element the
   stream would refuse) and of an svg, which do nothing; and a clone
   given an
   id already in the document ("old"), which makes a second element
   with it. Then, in a flush of its own, the retired op 9, which stops
   the flush *)
implement main0 () = let
  val buf = $A.alloc<byte>(CAP)
  (* SET_ATTR: [2][id][u8 name length][name][u16 value length][value] *)
  val off = put_byte(buf, 0, 2)
  val off = put_name(buf, off, "page")
  val off = put_byte(buf, off, 5)
  val () = $A.write_text(buf, off, $A.text_lit("title"), 5)
  val off = off + 5
  val off = put_name(buf, off, "now")
  (* CLONE_NODE: [8][new id][source id][parent id] *)
  val off = put_byte(buf, off, 8)
  val off = put_name(buf, off, "copy")
  val off = put_name(buf, off, "page")
  val off = put_name(buf, off, "sheet")
  val off = put_byte(buf, off, 8)
  val off = put_name(buf, off, "again")
  val off = put_name(buf, off, "page")
  val off = put_name(buf, off, "sheet")
  (* REMOVE_ATTR: [7][id][u8 name length][name] *)
  val off = put_byte(buf, off, 7)
  val off = put_name(buf, off, "copy")
  val off = put_byte(buf, off, 8)
  val () = $A.write_text(buf, off, $A.text_lit("tabindex"), 8)
  val off = off + 8
  val off = put_byte(buf, off, 2)
  val off = put_name(buf, off, "copy")
  val off = put_byte(buf, off, 5)
  val () = $A.write_text(buf, off, $A.text_lit("inert"), 5)
  val off = off + 5
  (* an empty value *)
  val off = put_byte(buf, off, 0)
  val off = put_byte(buf, off, 0)
  (* SET_SCROLL_LEFT and SET_SCROLL_TOP: [11 or 12][id][i32]: 640, 12 *)
  val off = put_byte(buf, off, 11)
  val off = put_name(buf, off, "copy")
  val off = put_i32(buf, off, 128, 2)
  val off = put_byte(buf, off, 12)
  val off = put_name(buf, off, "copy")
  val off = put_i32(buf, off, 12, 0)
  (* nothing there: nothing done *)
  val off = put_byte(buf, off, 11)
  val off = put_name(buf, off, "nowhere")
  val off = put_i32(buf, off, 1, 0)
  val off = put_byte(buf, off, 12)
  val off = put_name(buf, off, "nowhere")
  val off = put_i32(buf, off, 1, 0)
  (* a source the stream would refuse (a form): nothing made *)
  val off = put_byte(buf, off, 8)
  val off = put_name(buf, off, "refused")
  val off = put_name(buf, off, "form")
  val off = put_name(buf, off, "sheet")
  val off = put_byte(buf, off, 8)
  val off = put_name(buf, off, "lost")
  val off = put_name(buf, off, "nowhere")
  val off = put_name(buf, off, "sheet")
  (* a second "old" *)
  val off = put_byte(buf, off, 8)
  val off = put_name(buf, off, "old")
  val off = put_name(buf, off, "c2")
  val off = put_name(buf, off, "sheet")
  (* a source outside HTML's namespace (an svg): nothing made *)
  val off = put_byte(buf, off, 8)
  val off = put_name(buf, off, "foreign")
  val off = put_name(buf, off, "drawing")
  val off = put_name(buf, off, "sheet")
  val () = $DM.dom_flush(buf, off)
  (* 9, retired: a stream in its old shape stops (check.mjs prints the
     error) *)
  val off = put_byte(buf, 0, 9)
  val off = put_name(buf, off, "copy")
  val off = put_i32(buf, off, 1, 0)
  val off = put_i32(buf, off, 2, 0)
  val () = $DM.dom_flush(buf, off)
in $A.free<byte>(buf) end
