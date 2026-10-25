#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload GA = "wasm.bats-packages.dev/bridge/src/google_account.sats"

(* Asking matched without TokenThrown: a request that threw would go unhandled, as if a token were given *)
fn f {lc:agz}{nc:pos}{ls:agz}{ns:pos}
  (client: !$A.borrow(byte, lc, nc), client_len: int nc,
   scope: !$A.borrow(byte, ls, ns), scope_len: int ns): void =
  $P.finish<$GA.token_answer>($GA.google_token_get_answer(client, client_len, scope, scope_len), llam (answer) =>
    case+ answer of
    | ~$GA.TokenGiven(token, account) => let
        val () = $DC.blob_free(token)
      in (case+ account of ~$R.some(a) => $DC.blob_free(a) | ~$R.none() => ()) end
    | ~$GA.TokenCanceled() => ()
    | ~$GA.TokenRefused(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$GA.TokenNotHere() => ()
    | ~$GA.TokenLoadFailed(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$GA.TokenAnswerUnread(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$GA.TokenUnexpected(_) => ())
