#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A listener takes its event's bytes during the call, and frees them;
   one that wants none ignores the payload *)
fn f {lb:agz}{n:pos} (t: !$A.borrow(byte, lb, n), tn: int n): void = let
  val () = $EV.listen_document(t, tn, 0, llam (payload) =>
    case+ $EV.event_take(payload) of
    | ~$R.some(b) => let
        val k = $BD.blob_len(b)
        val () = $BD.blob_free(b)
      in k end
    | ~$R.none() => 0)
in $EV.listen_document(t, tn, 1, llam (_) => 0) end
