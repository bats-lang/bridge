#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A fetched response is claimed once: its body read whole, then freed *)
fn f (h: Int): int =
  case+ $FE.fetch_claim(h) of
  | ~$R.none() => 0
  | ~$R.some(@(_, b)) => let
      val n = $BD.blob_len(b)
    in
      if n <= 0 then let val () = $BD.blob_free(b) in 0 end
      else if n > 1048576 then let val () = $BD.blob_free(b) in 0 end
      else let
        val buf = $A.alloc<byte>(n)
        val () = $BD.blob_read(b, 0, buf, n)
        val () = $BD.blob_free(b)
        val () = $A.free<byte>(buf)
      in n end
    end
