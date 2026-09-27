#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"

(* A read must lie inside the file: [1, n + 1) does not *)
fn f (h: Int): int =
  case+ $BF.file_claim(h) of
  | ~$R.none() => 0
  | ~$R.some(fl) => let
      val n = $BF.file_size(fl)
    in
      if n <= 0 then let val () = $BF.file_close(fl) in 0 end
      else if n > 1048576 then let val () = $BF.file_close(fl) in 0 end
      else let
        val buf = $A.alloc<byte>(n)
        val () = $BF.file_read(fl, 1, buf, n)
        val () = $BF.file_close(fl)
        val () = $A.free<byte>(buf)
      in n end
    end
