#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload NO = "wasm.bats-packages.dev/bridge/src/notify.sats"
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A subscription matched without SubscribeFailed *)
fn f (): void =
  $P.finish<$NO.subscription>($NO.notify_push_get_subscription(), llam (found) =>
    case+ found of
    | ~$NO.Subscribed(blob) => $DC.blob_free(blob)
    | ~$NO.NotSubscribed() => ())
