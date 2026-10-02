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
   parent *)
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

(* The flush's SET_ATTR (2): attribute name of element id, value *)
fn set_attr_op {l:agz}{offset:nat}{ni,nn,nv:nat | ni < 256; nn < 256; nv < 256; offset + 6 + ni + nn + nv <= BUFFER_SIZE}
  (buffer: !$A.arr(byte, l, BUFFER_SIZE), offset: int offset, id: string ni, name: string nn, value: string nv)
  : int(offset + 6 + ni + nn + nv) = let
  val () = $A.write_byte(buffer, offset, 2)
  val () = $A.write_u16le(buffer, offset + 1, g1u2i(string1_length(id)))
  val after_id = put(buffer, offset + 3, id)
  val () = $A.write_byte(buffer, after_id, g1u2i(string1_length(name)))
  val after_name = put(buffer, after_id + 1, name)
  val () = $A.write_u16le(buffer, after_name, g1u2i(string1_length(value)))
in put(buffer, after_name + 2, value) end

(* Writes the flush's operations by hand, as code that does not go
   through the dom package's types could: event handlers (onclick,
   ONLOAD) and javascript: URLs (with a space before, in mixed case,
   with a tab inside, as a button's formaction) among attributes that
   are harmless. The flush must set only the harmless ones *)
implement main0 () = let
  val buffer = $A.alloc<byte>(1024)
  val offset = create_op(buffer, 0, "d1", "bats-root", "div")
  val offset = set_attr_op(buffer, offset, "d1", "onclick", "alert(1)")
  val offset = set_attr_op(buffer, offset, "d1", "ONLOAD", "alert(1)")
  val offset = set_attr_op(buffer, offset, "d1", "title", "kept")
  val offset = create_op(buffer, offset, "a1", "bats-root", "a")
  val offset = set_attr_op(buffer, offset, "a1", "href", " JavaScript:alert(1)")
  val offset = create_op(buffer, offset, "a2", "bats-root", "a")
  val offset = set_attr_op(buffer, offset, "a2", "href", "java\tscript:alert(1)")
  val offset = create_op(buffer, offset, "f1", "bats-root", "button")
  val offset = set_attr_op(buffer, offset, "f1", "formaction", "javascript:alert(1)")
  val offset = create_op(buffer, offset, "a3", "bats-root", "a")
  val offset = set_attr_op(buffer, offset, "a3", "href", "https://example.com/")
  val offset = create_op(buffer, offset, "i1", "bats-root", "img")
  val offset = set_attr_op(buffer, offset, "i1", "src", "blob:http://localhost/picture")
  val () = dom_flush(buffer, offset)
in $A.free<byte>(buffer) end
