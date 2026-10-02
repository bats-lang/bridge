#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A decompression matched without DecompressFailed *)
fn f (): void = let
  val key = $A.alloc<byte>(3)
  val () = $A.write_text(key, 0, $A.text_lit("abc"), 3)
  val @(frozen, borrowed) = $A.freeze<byte>(key)
  val () = $P.finish<$DC.decompressed>($DC.decompress(borrowed, 3, $DC.Gzip()), llam (result) =>
    case+ result of
    | ~$DC.Decompressed(blob) => $DC.blob_free(blob))
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end
