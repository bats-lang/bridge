#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload PL = "wasm.bats-packages.dev/bridge/src/platform.sats"

(* An Unexpected system whose fact is dropped: the text it keeps would leak *)
fn f (os: $PL.os_reading): void =
  case+ os of
  | ~$PL.OsAndroid() => ()
  | ~$PL.OsIos() => ()
  | ~$PL.OsIpadOs() => ()
  | ~$PL.OsMacOs() => ()
  | ~$PL.OsWindows() => ()
  | ~$PL.OsLinux() => ()
  | ~$PL.OsChromeOs() => ()
  | ~$PL.OsUnexpected(_, a, b, c, _) => let val () = $PL.platform_fact_free(a) val () = $PL.platform_fact_free(b) in $PL.platform_fact_free(c) end
