#target native
#include "share/atspre_staload.hats"
#use array as A
#use pwa as P

(* Writes dist/pwa/bridge.js and dist/pwa/app.wasm (a copy of the
   wasm binary app) *)
implement main0 () = let
  val assets = $A.alloc<byte>(1)
  val () = $P.create_pwa("Pointer", "dev.bats.pointer",
    "dist/debug/app.wasm", "app.wasm", "dist/pwa",
    assets, 0, 1)
  val () = $A.free<byte>(assets)
in end
