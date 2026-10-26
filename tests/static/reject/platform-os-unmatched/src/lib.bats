#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload PL = "wasm.bats-packages.dev/bridge/src/platform.sats"

(* A system matched without OsChromeOs: a Chromebook would go unhandled *)
fn f (os: $PL.os_reading): void =
  case+ os of
  | ~$PL.OsAndroid() => ()
  | ~$PL.OsIos() => ()
  | ~$PL.OsIpadOs() => ()
  | ~$PL.OsMacOs() => ()
  | ~$PL.OsWindows() => ()
  | ~$PL.OsLinux() => ()
  | ~$PL.OsUnexpected(_, a, b, c, d) => let val () = $PL.platform_fact_free(a) val () = $PL.platform_fact_free(b) val () = $PL.platform_fact_free(c) in $PL.platform_fact_free(d) end
