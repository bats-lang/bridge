#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"

(* A body fetched as a file is read whole, then closed *)
fn f (got: $FE.fetched_file): int =
  case+ got of
  | ~$FE.NoFileResponse() => 0
  | ~$FE.RespondedFile(_, fl) => let
      val n = $BF.file_size(fl)
    in
      if n <= 0 then let val () = $BF.file_close(fl) in 0 end
      else if n > 1048576 then let val () = $BF.file_close(fl) in 0 end
      else let
        val buf = $A.alloc<byte>(n)
        val () = $BF.file_read(fl, 0, buf, n)
        val () = $BF.file_close(fl)
        val () = $A.free<byte>(buf)
      in n end
    end
