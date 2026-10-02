#target native
#include "share/atspre_staload.hats"
#use array as A
#use pwa as P

(* Writes dist/pwa/, with service-worker.js, as an app's PWA is written:
   the worker check.mjs runs. No wasm is built, so none is copied *)
implement main0 () = let
  val assets = $A.alloc<byte>(1)
  val () = $P.create_pwa("Service worker", "dev.bats.service-worker",
    "dist/debug/app.wasm", "app.wasm", "dist/pwa",
    assets, 0, 1)
  val () = $A.free<byte>(assets)
in end
