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

(* The flush's SET_TEXT (1): the text of element id *)
fn set_text_op {l:agz}{offset:nat}{ni,nt:nat | ni < 256; nt < 256; offset + 5 + ni + nt <= BUFFER_SIZE}
  (buffer: !$A.arr(byte, l, BUFFER_SIZE), offset: int offset, id: string ni, text: string nt)
  : int(offset + 5 + ni + nt) = let
  val () = $A.write_byte(buffer, offset, 1)
  val () = $A.write_u16le(buffer, offset + 1, g1u2i(string1_length(id)))
  val after_id = put(buffer, offset + 3, id)
  val () = $A.write_u16le(buffer, after_id, g1u2i(string1_length(text)))
in put(buffer, after_id + 2, text) end

(* A text and an id that begin with a byte order mark (U+FEFF, the bytes
   EF BB BF), written as the flush's SET_TEXT and CREATE_ELEMENT operations
   that Bats hands JS: the page keeps them, the mark included. A plain
   paragraph is the control *)
implement main0 () = let
  val buffer = $A.alloc<byte>(1024)
  val offset = create_op(buffer, 0, "﻿s1", "bats-root", "span")
  val offset = set_text_op(buffer, offset, "﻿s1", "﻿text")
  val offset = create_op(buffer, offset, "p1", "bats-root", "p")
  val offset = set_text_op(buffer, offset, "p1", "plain")
  val () = dom_flush(buffer, offset)
in $A.free<byte>(buffer) end
