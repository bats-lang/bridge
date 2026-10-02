#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"

(* A closed file is gone on the JS side: it cannot be read *)
fn f (h: $BF.file_handle): int =
  case+ $BF.file_claim(h) of
  | ~$R.none() => 0
  | ~$R.some(fl) => let
      val n = $BF.file_size(fl)
    in
      if n <= 0 then let val () = $BF.file_close(fl) in 0 end
      else if n > 1048576 then let val () = $BF.file_close(fl) in 0 end
      else let
        val buf = $A.alloc<byte>(n)
        val () = $BF.file_close(fl)
        val () = $BF.file_read(fl, 0, buf, n)
        val () = $A.free<byte>(buf)
      in n end
    end
