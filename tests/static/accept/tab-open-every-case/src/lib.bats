#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload BT = "wasm.bats-packages.dev/bridge/src/browser_tab.sats"

(* An open matched in every case, its text freed; the old form matched too
   (kept for one version, bridge#240); an answer let go is freed by its
   dispose *)
fn f {lb:agz}{n:nat}
  (url: !$A.borrow(byte, lb, n), url_len: int n): void = let
  val () = $P.finish<$BT.tab_open_answer>($BT.browser_tab_open_answer(url, url_len), llam (answer) =>
    case+ answer of
    | ~$BT.TabOpenDone() => ()
    | ~$BT.TabOpenNotHttps() => ()
    | ~$BT.TabOpenNotHere() => ()
    | ~$BT.TabOpenRejected(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$BT.TabOpenThrown(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$BT.TabOpenUnexpected(_) => ())
  val () = $P.finish<$BT.tab_opened>($BT.browser_tab_open(url, url_len), llam (old) =>
    case+ old of
    | $BT.TabOpened() => ()
    | $BT.TabNotOpened() => ())
  val () = $P.discard<$BT.tab_open_answer>($BT.browser_tab_open_answer(url, url_len))
in () end
