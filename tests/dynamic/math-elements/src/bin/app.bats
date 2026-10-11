#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload "wasm.bats-packages.dev/bridge/src/dom.bats"

stadef BUFFER_SIZE = 1024

(* s's bytes at offset; the offset after them *)
fn put {l:agz}{offset,n:nat | offset + n <= BUFFER_SIZE}
  (buffer: !$A.arr(byte, l, BUFFER_SIZE), offset: int offset, s: string n): int(offset + n) = let
  val n = g1u2i(string1_length(s))
  val () = $A.write_text(buffer, offset, $A.text_lit(s), n)
in offset + n end

(* The flush's CREATE_ELEMENT (4): a <tag id=id> as the last child of
   parent (tag "math:mi" is the MathML element mi) *)
fn create_op {l:agz}{offset:nat}{ni,np,nt:nat | ni < 256; np < 256; nt < 256; offset + 6 + ni + np + nt <= BUFFER_SIZE}
  (buffer: !$A.arr(byte, l, BUFFER_SIZE), offset: int offset, id: string ni, parent: string np, tag: string nt)
  : int(offset + 6 + ni + np + nt) = let
  val () = $A.write_byte(buffer, offset, 4)
  val () = $A.write_u16le(buffer, offset + 1, g1u2i(string1_length(id)))
  val after_id = put(buffer, offset + 3, id)
  val () = $A.write_u16le(buffer, after_id, g1u2i(string1_length(parent)))
  val after_parent = put(buffer, after_id + 2, parent)
  val () = $A.write_byte(buffer, after_parent, g1u2i(string1_length(tag)))
in put(buffer, after_parent + 1, tag) end

(* The flush's SET_TEXT (1): the text of element id *)
fn set_text_op {l:agz}{offset:nat}{ni,nt:nat | ni < 256; nt < 256; offset + 5 + ni + nt <= BUFFER_SIZE}
  (buffer: !$A.arr(byte, l, BUFFER_SIZE), offset: int offset, id: string ni, text: string nt)
  : int(offset + 5 + ni + nt) = let
  val () = $A.write_byte(buffer, offset, 1)
  val () = $A.write_u16le(buffer, offset + 1, g1u2i(string1_length(id)))
  val after_id = put(buffer, offset + 3, id)
  val () = $A.write_u16le(buffer, after_id, g1u2i(string1_length(text)))
in put(buffer, after_id + 2, text) end

(* The flush's CLONE_NODE (8): a copy of source, as parent's last child, with id *)
fn clone_op {l:agz}{offset:nat}{ni,ns,np:nat | ni < 256; ns < 256; np < 256; offset + 7 + ni + ns + np <= BUFFER_SIZE}
  (buffer: !$A.arr(byte, l, BUFFER_SIZE), offset: int offset, id: string ni, source: string ns, parent: string np)
  : int(offset + 7 + ni + ns + np) = let
  val () = $A.write_byte(buffer, offset, 8)
  val () = $A.write_u16le(buffer, offset + 1, g1u2i(string1_length(id)))
  val after_id = put(buffer, offset + 3, id)
  val () = $A.write_u16le(buffer, after_id, g1u2i(string1_length(source)))
  val after_source = put(buffer, after_id + 2, source)
  val () = $A.write_u16le(buffer, after_source, g1u2i(string1_length(parent)))
in put(buffer, after_source + 2, parent) end

(* Writes the flush's operations by hand: a MathML equation (math, mrow,
   msup with an identifier and a number, as a page would make for x
   squared), an HTML paragraph among them, and, as code that does not go
   through the dom package's types could, a maction, an annotation-xml, a
   custom element's name and an unknown prefix, which must not be made;
   then the equation cloned, which keeps its MathML elements *)
implement main0 () = let
  val buffer = $A.alloc<byte>(1024)
  val offset = create_op(buffer, 0, "q1", "bats-root", "math:math")
  val offset = create_op(buffer, offset, "r1", "q1", "math:mrow")
  val offset = create_op(buffer, offset, "u1", "r1", "math:msup")
  val offset = create_op(buffer, offset, "i1", "u1", "math:mi")
  val offset = set_text_op(buffer, offset, "i1", "x")
  val offset = create_op(buffer, offset, "n1", "u1", "math:mn")
  val offset = set_text_op(buffer, offset, "n1", "2")
  val offset = create_op(buffer, offset, "a1", "q1", "math:maction")
  val offset = create_op(buffer, offset, "a2", "q1", "math:annotation-xml")
  val offset = create_op(buffer, offset, "a3", "q1", "math:my-element")
  val offset = create_op(buffer, offset, "a4", "q1", "svg:rect")
  val offset = create_op(buffer, offset, "p1", "bats-root", "p")
  val offset = set_text_op(buffer, offset, "p1", "after")
  val offset = clone_op(buffer, offset, "q2", "q1", "bats-root")
  val () = dom_flush(buffer, offset)
in $A.free<byte>(buffer) end
