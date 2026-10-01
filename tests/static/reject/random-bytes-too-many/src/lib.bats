#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload RN = "wasm.bats-packages.dev/bridge/src/random.sats"

(* getRandomValues fills at most 65536 bytes a call: 65537 is too many *)
fn f (): void = let
  val buf = $A.alloc<byte>(65537)
  val () = $RN.random_bytes(buf, 65537)
  val () = $A.free<byte>(buf)
in end
