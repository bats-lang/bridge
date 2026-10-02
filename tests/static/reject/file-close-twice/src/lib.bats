#include "share/atspre_staload.hats"
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"

(* A file is closed once: a copy of it cannot outlive the close *)
fn f (h: $BF.file_handle): int =
  case+ $BF.file_claim(h) of
  | ~$R.none() => 0
  | ~$R.some(fl) => let
      val g = fl
      val () = $BF.file_close(fl)
      val () = $BF.file_close(g)
    in 1 end
