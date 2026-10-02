#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload CL = "wasm.bats-packages.dev/bridge/src/clipboard.sats"
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload NO = "wasm.bats-packages.dev/bridge/src/notify.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"

(* Every case of each matched, its blob freed or its file closed; a
   result let go is freed by its dispose *)
fn f (): void = let
  val key = $A.alloc<byte>(3)
  val () = $A.write_text(key, 0, $A.text_lit("abc"), 3)
  val @(frozen, borrowed) = $A.freeze<byte>(key)
  val () = $P.finish<$CL.clip>($CL.clipboard_read(), llam (found) =>
    case+ found of
    | ~$CL.Clipped(blob) => $DC.blob_free(blob)
    | ~$CL.ClipEmpty() => ()
    | ~$CL.ClipRefused() => ())
  val () = $P.finish<$NO.subscription>($NO.notify_push_subscribe(borrowed, 3), llam (found) =>
    case+ found of
    | ~$NO.Subscribed(blob) => $DC.blob_free(blob)
    | ~$NO.NotSubscribed() => ()
    | ~$NO.SubscribeFailed() => ())
  val () = $P.finish<$BF.opened>($BF.file_open_at(borrowed, 3, 0), llam (found) =>
    case+ found of
    | ~$BF.Opened(f) => $BF.file_close(f)
    | ~$BF.NotOpened() => ()
    | ~$BF.OpenFailed() => ())
  val () = $P.finish<$DC.decompressed>($DC.decompress(borrowed, 3, $DC.Deflate()), llam (result) =>
    case+ result of
    | ~$DC.Decompressed(blob) => $DC.blob_free(blob)
    | ~$DC.DecompressFailed() => ())
  val () = $P.discard<$BF.opened>($BF.file_open(borrowed, 3))
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end
