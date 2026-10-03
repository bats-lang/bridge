#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload DM = "wasm.bats-packages.dev/bridge/src/dom.bats"

#define CAP 128

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

(* Through dom_flush: element "page" (check.mjs made it) cloned into
   "sheet" as "copy", and again as "again"; then the copy's tabindex
   removed and inert set, as any element's; and a clone of an element
   that is not there, which makes nothing *)
implement main0 () = let
  val buf = $A.alloc<byte>(CAP)
  (* CLONE_NODE: [8][new id][source id][parent id] *)
  val off = put_byte(buf, 0, 8)
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
  (* SET_ATTR: [2][id][u8 name length][name][u16 value length][value] *)
  val off = put_byte(buf, off, 2)
  val off = put_name(buf, off, "copy")
  val off = put_byte(buf, off, 5)
  val () = $A.write_text(buf, off, $A.text_lit("inert"), 5)
  val off = off + 5
  (* an empty value *)
  val off = put_byte(buf, off, 0)
  val off = put_byte(buf, off, 0)
  val off = put_byte(buf, off, 8)
  val off = put_name(buf, off, "lost")
  val off = put_name(buf, off, "nowhere")
  val off = put_name(buf, off, "sheet")
  val () = $DM.dom_flush(buf, off)
in $A.free<byte>(buf) end
