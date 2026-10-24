#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload GA = "wasm.bats-packages.dev/bridge/src/google_account.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"

(* Asks for a token with google_token_get_answer (check.mjs plays Google
   Identity Services), says how it ended in the address's hash, as a line
   (check.mjs prints each hash), and asks again with the old
   google_token_get, which it also says. The answer of
   google_token_get_answer is matched with case+, every constructor
   visible, and the old google_token_get is called too (it is kept for one
   version, bridge#235), so an edit cannot drop it: it says only what it
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
implement $P.dispose<$GA.token_answer>(answer) =
  case+ answer of
  | ~$GA.TokenGiven(token, account) => let
      val () = $BD.blob_free(token)
    in case+ account of ~$R.some(a) => $BD.blob_free(a) | ~$R.none() => () end
  | ~$GA.TokenCanceled() => ()
  | ~$GA.TokenRefused(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$GA.TokenNotHere() => ()
  | ~$GA.TokenLoadFailed(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$GA.TokenThrown(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$GA.TokenAnswerUnread(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$GA.TokenUnexpected(_) => ()

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

(* The text a call was rejected with, as the next hash after the outcome's name *)
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

fn say_answer (answer: $GA.token_answer): void =
  case+ answer of
  | ~$GA.TokenGiven(token, account) => let
      val () = say_text("given")
      val () = $BD.blob_free(token)
    in case+ account of ~$R.some(a) => $BD.blob_free(a) | ~$R.none() => () end
  | ~$GA.TokenCanceled() => say_text("canceled")
  | ~$GA.TokenRefused(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("refused") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("refused: no text"))
  | ~$GA.TokenNotHere() => say_text("not here")
  | ~$GA.TokenLoadFailed(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("load failed") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("load failed: no text"))
  | ~$GA.TokenThrown(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("thrown") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("thrown: no text"))
  | ~$GA.TokenAnswerUnread(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("unread") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("unread: no text"))
  | ~$GA.TokenUnexpected(_) => say_text("unexpected")

fn say_old (old: $GA.google_token): void =
  case+ old of
  | ~$GA.GoogleToken(token, account) => let
      val () = say_text("old: token")
      val () = $BD.blob_free(token)
    in case+ account of ~$R.some(a) => $BD.blob_free(a) | ~$R.none() => () end
  | ~$GA.GoogleNoAccount() => say_text("old: no account")
  | ~$GA.GoogleCanceled() => say_text("old: canceled")
  | ~$GA.GoogleRefused() => say_text("old: refused")
  | ~$GA.GoogleUnavailable() => say_text("old: unavailable")

(* s's bytes in a fresh array of exactly its length *)
fn bytes {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

(* Asks with google_token_get_answer for client-id and scope *)
fn ask_answer (): $P.promise($GA.token_answer, $P.Chained) = let
  val @(client_frozen, client) = $A.freeze<byte>(bytes("client-id"))
  val @(scope_frozen, scope) = $A.freeze<byte>(bytes("scope"))
  val asked = $GA.google_token_get_answer(client, 9, scope, 5)
  val () = $A.drop<byte>(scope_frozen, scope)
  val () = $A.free<byte>($A.thaw<byte>(scope_frozen))
  val () = $A.drop<byte>(client_frozen, client)
  val () = $A.free<byte>($A.thaw<byte>(client_frozen))
in asked end

(* Asks with the old google_token_get for client-id and scope *)
fn ask_old (): $P.promise($GA.google_token, $P.Chained) = let
  val @(client_frozen, client) = $A.freeze<byte>(bytes("client-id"))
  val @(scope_frozen, scope) = $A.freeze<byte>(bytes("scope"))
  val asked = $GA.google_token_get(client, 9, scope, 5)
  val () = $A.drop<byte>(scope_frozen, scope)
  val () = $A.free<byte>($A.thaw<byte>(scope_frozen))
  val () = $A.drop<byte>(client_frozen, client)
  val () = $A.free<byte>($A.thaw<byte>(client_frozen))
in asked end

implement main0 () =
  $P.finish<$GA.token_answer>(ask_answer(), llam (answer) => let
    val () = say_answer(answer)
  in $P.finish<$GA.google_token>(ask_old(), llam (old) => say_old(old)) end)
