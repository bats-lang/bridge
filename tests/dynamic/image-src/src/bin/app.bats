#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload DM = "wasm.bats-packages.dev/bridge/src/dom.bats"

(* Gives the image "pic" a new picture: one byte of image/png *)
fn picture_set (shade: int): void = let
  val id = $A.alloc<byte>(3)
  val () = $A.write_text(id, 0, $A.text_lit("pic"), 3)
  val data = $A.alloc<byte>(1)
  val () = $A.set<byte>(data, 0, $A.int2byte(g1ofg0(shade) mod 256))
  val mime = $A.alloc<byte>(9)
  val () = $A.write_text(mime, 0, $A.text_lit("image/png"), 9)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(id)
  val @(data_frozen, data_bytes) = $A.freeze<byte>(data)
  val @(mime_frozen, mime_bytes) = $A.freeze<byte>(mime)
  val () = $DM.set_image_src(id_bytes, 3, data_bytes, 1, mime_bytes, 9)
  val () = $A.drop<byte>(id_frozen, id_bytes)
  val () = $A.drop<byte>(data_frozen, data_bytes)
  val () = $A.drop<byte>(mime_frozen, mime_bytes)
  val () = $A.free<byte>($A.thaw<byte>(id_frozen))
  val () = $A.free<byte>($A.thaw<byte>(data_frozen))
  val () = $A.free<byte>($A.thaw<byte>(mime_frozen))
in end

(* The picture of "pic" replaced three times: the first two blob URLs
   (blob:1, blob:2) are the replaced ones; check.mjs holds blob:1 in a
   copy of the image that has not loaded *)
implement main0 () = let
  val () = picture_set(1)
  val () = picture_set(2)
  val () = picture_set(3)
in end
