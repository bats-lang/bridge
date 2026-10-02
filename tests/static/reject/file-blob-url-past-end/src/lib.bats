#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A blob URL's bytes must lie inside the file: [1, n + 1) does not *)
fn url {n:pos} (fl: !$BF.infile(n), n: int n): int = let
  val mime = $A.alloc<byte>(10)
  val () = $A.write_text(mime, 0, $A.text_lit("audio/mpeg"), 10)
  val @(frozen, borrowed) = $A.freeze<byte>(mime)
  val made = $BF.file_blob_url(fl, 1, n, borrowed, 10)
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in
  case+ made of
  | ~$R.none() => 0
  | ~$R.some(u) => let val () = $BD.blob_free(u) in 1 end
end

fn f (h: $BF.file_handle): int =
  case+ $BF.file_claim(h) of
  | ~$R.none() => 0
  | ~$R.some(fl) => let
      val n = $BF.file_size(fl)
    in
      if n <= 0 then let val () = $BF.file_close(fl) in 0 end
      else let
        val made = url(fl, n)
        val () = $BF.file_close(fl)
      in made end
    end
