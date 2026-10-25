#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload BT = "wasm.bats-packages.dev/bridge/src/browser_tab.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"

(* Opens an https address and then one that is not, each with
   browser_tab_open_answer and then with the old browser_tab_open, and says
   how each ended in the address's hash, as a line: check.mjs prints each
   hash. The answer of browser_tab_open_answer is matched with case+, every
   constructor visible, and the old browser_tab_open is called too (it is
   kept for one version, bridge#240), so an edit cannot drop it: it says only
   opened or not opened, as it always did (bridge#186). *)

(* Answers nobody took, freed: before their first use *)
implement $P.dispose<$BT.tab_opened>(_) = ()
implement $P.dispose<$BT.tab_open_answer>(answer) =
  case+ answer of
  | ~$BT.TabOpenDone() => ()
  | ~$BT.TabOpenNotHttps() => ()
  | ~$BT.TabOpenNotHere() => ()
  | ~$BT.TabOpenRejected(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$BT.TabOpenThrown(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$BT.TabOpenUnexpected(_) => ()

fn say {l:agz}{n:pos | n <= 4096} (a: $A.arr(byte, l, n), n: int n): void = let
  val @(frozen, borrowed) = $A.freeze<byte>(a)
  val () = $NAV.set_hash(borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn say_text {n:pos | n < 256} (s: string n): void = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in say(a, n) end

(* A blob's bytes, as the next hash *)
fn say_blob {n:nat} (blob: !$BD.dblob(n)): void = let
  val n = $BD.blob_len(blob)
in
  if n <= 0 then say_text("no text")
  else if n > 4096 then say_text("long text")
  else let
    val a = $A.alloc<byte>(n)
    val () = $BD.blob_read(blob, 0, a, n)
  in say(a, n) end
end

fn say_answer (answer: $BT.tab_open_answer): void =
  case+ answer of
  | ~$BT.TabOpenDone() => say_text("opened")
  | ~$BT.TabOpenNotHttps() => say_text("not https")
  | ~$BT.TabOpenNotHere() => say_text("not here")
  | ~$BT.TabOpenRejected(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("rejected") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("rejected: no text"))
  | ~$BT.TabOpenThrown(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("thrown") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("thrown: no text"))
  | ~$BT.TabOpenUnexpected(_) => say_text("unexpected")

fn say_old (old: $BT.tab_opened): void =
  case+ old of
  | $BT.TabOpened() => say_text("old: opened")
  | $BT.TabNotOpened() => say_text("old: not opened")

(* s's bytes in a fresh array of exactly its length *)
fn bytes {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

fn open_answer {n:pos | n < 256} (s: string n): $P.promise($BT.tab_open_answer, $P.Chained) = let
  val @(frozen, borrowed) = $A.freeze<byte>(bytes(s))
  val answered = $BT.browser_tab_open_answer(borrowed, g1u2i(string1_length(s)))
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in answered end

fn open_old {n:pos | n < 256} (s: string n): $P.promise($BT.tab_opened, $P.Chained) = let
  val @(frozen, borrowed) = $A.freeze<byte>(bytes(s))
  val opened = $BT.browser_tab_open(borrowed, g1u2i(string1_length(s)))
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in opened end

implement main0 () =
  $P.finish<$BT.tab_open_answer>(open_answer("https://example.com/a"), llam (answer) => let
    val () = say_answer(answer)
  in
    $P.finish<$BT.tab_opened>(open_old("https://example.com/a"), llam (old) => let
      val () = say_old(old)
    in
      $P.finish<$BT.tab_open_answer>(open_answer("http://example.com/b"), llam (refused) => let
        val () = say_answer(refused)
      in
        $P.finish<$BT.tab_opened>(open_old("http://example.com/b"), llam (refused_old) =>
          say_old(refused_old))
      end)
    end)
  end)
