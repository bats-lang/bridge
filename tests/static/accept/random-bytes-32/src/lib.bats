#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload RN = "wasm.bats-packages.dev/bridge/src/random.sats"

(* 32 random bytes, as a PKCE verifier's or a device id's source *)
fn f (): void = let
  val buf = $A.alloc<byte>(32)
  val () = $RN.random_bytes(buf, 32)
  val () = $A.free<byte>(buf)
in end
