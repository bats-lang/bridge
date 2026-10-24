#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload GA = "wasm.bats-packages.dev/bridge/src/google_account.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"

(* Gets a token (check.mjs plays Google Identity Services), signs out with
   each form and says how each ended in the address's hash, as a line:
   check.mjs prints each hash. The answer of google_sign_out_answer is
   matched with case+, every constructor visible, and the old
   google_sign_out is called too (it is kept for one version, bridge#231),
   so an edit cannot drop it: it says only signed out or failed, as it
   always did (bridge#186). *)

(* Answers nobody took, freed: before their first use (as google-web does) *)
implement $P.dispose<$GA.google_token>(answer) =
  case+ answer of
  | ~$GA.GoogleToken(token, account) => let
      val () = $BD.blob_free(token)
    in case+ account of ~$R.some(a) => $BD.blob_free(a) | ~$R.none() => () end
  | ~$GA.GoogleNoAccount() => ()
  | ~$GA.GoogleCanceled() => ()
  | ~$GA.GoogleRefused() => ()
  | ~$GA.GoogleUnavailable() => ()
implement $P.dispose<$GA.google_signed_out>(_) = ()
implement $P.dispose<$GA.sign_out_answer>(answer) =
  case+ answer of
  | ~$GA.SignOutDone() => ()
  | ~$GA.SignOutNotHere() => ()
  | ~$GA.SignOutRevokeFailed(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$GA.SignOutLoadFailed(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$GA.SignOutThrown(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$GA.SignOutAnswerOdd(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$GA.SignOutAnswerUnread(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$GA.SignOutUnexpected(_) => ()

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

(* The text a call rejected with, as the next hash after the outcome's name *)
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

fn say_answer (answer: $GA.sign_out_answer): void =
  case+ answer of
  | ~$GA.SignOutDone() => say_text("done")
  | ~$GA.SignOutNotHere() => say_text("not here")
  | ~$GA.SignOutRevokeFailed(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("revoke failed") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("revoke failed: no text"))
  | ~$GA.SignOutLoadFailed(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("load failed") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("load failed: no text"))
  | ~$GA.SignOutThrown(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("thrown") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("thrown: no text"))
  | ~$GA.SignOutAnswerOdd(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("odd") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("odd: no text"))
  | ~$GA.SignOutAnswerUnread(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("unread") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("unread: no text"))
  | ~$GA.SignOutUnexpected(_) => say_text("unexpected")

(* s's bytes in a fresh array of exactly its length *)
fn bytes {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

(* Asks for a token for client-id and scope *)
fn ask (): $P.promise($GA.google_token, $P.Chained) = let
  val @(client_frozen, client) = $A.freeze<byte>(bytes("client-id"))
  val @(scope_frozen, scope) = $A.freeze<byte>(bytes("scope"))
  val asked = $GA.google_token_get(client, 9, scope, 5)
  val () = $A.drop<byte>(scope_frozen, scope)
  val () = $A.free<byte>($A.thaw<byte>(scope_frozen))
  val () = $A.drop<byte>(client_frozen, client)
  val () = $A.free<byte>($A.thaw<byte>(client_frozen))
in asked end

(* An answer to asking for a token, freed *)
fn drop_token (answer: $GA.google_token): void =
  case+ answer of
  | ~$GA.GoogleToken(token, account) => let
      val () = $BD.blob_free(token)
    in case+ account of ~$R.some(a) => $BD.blob_free(a) | ~$R.none() => () end
  | ~$GA.GoogleNoAccount() => ()
  | ~$GA.GoogleCanceled() => ()
  | ~$GA.GoogleRefused() => ()
  | ~$GA.GoogleUnavailable() => ()

implement main0 () = let
  val signed = $P.and_then<$GA.google_token><$GA.sign_out_answer>(ask(), llam (token) => let
    val () = drop_token(token)
  in $GA.google_sign_out_answer() end)
in
  $P.finish<$GA.sign_out_answer>(signed, llam (answer) => let
    val () = say_answer(answer)
    val again = $P.and_then<$GA.google_token><$GA.google_signed_out>(ask(), llam (token) => let
      val () = drop_token(token)
    in $GA.google_sign_out() end)
  in
    $P.finish<$GA.google_signed_out>(again, llam (old) =>
      case+ old of
      | $GA.GoogleSignedOut() => say_text("old: signed out")
      | $GA.GoogleSignOutFailed() => say_text("old: failed"))
  end)
end
