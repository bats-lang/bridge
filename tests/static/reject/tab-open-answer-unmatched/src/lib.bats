#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload BT = "wasm.bats-packages.dev/bridge/src/browser_tab.sats"

(* An open matched without TabOpenThrown: a thrown one would go
   unhandled *)
fn f {lb:agz}{n:nat}
  (url: !$A.borrow(byte, lb, n), url_len: int n): void =
  $P.finish<$BT.tab_open_answer>($BT.browser_tab_open_answer(url, url_len), llam (answer) =>
    case+ answer of
    | ~$BT.TabOpenDone() => ()
    | ~$BT.TabOpenNotHttps() => ()
    | ~$BT.TabOpenNotHere() => ()
    | ~$BT.TabOpenRejected(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$BT.TabOpenUnexpected(_) => ())
