#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B

staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload GA = "wasm.bats-packages.dev/bridge/src/google_account.bats"

(* Answers nobody took, freed: before their first use *)
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

(* Whether an answer was a token (freed) *)
fn is_token (answer: $GA.google_token): bool =
  case+ answer of
  | ~$GA.GoogleToken(token, account) => let
      val () = $BD.blob_free(token)
      val () = (case+ account of ~$R.some(a) => $BD.blob_free(a) | ~$R.none() => ())
    in true end
  | ~$GA.GoogleNoAccount() => false
  | ~$GA.GoogleCanceled() => false
  | ~$GA.GoogleRefused() => false
  | ~$GA.GoogleUnavailable() => false

(* Whether an answer was the reader closing the window *)
fn is_canceled (answer: $GA.google_token): bool =
  case+ answer of
  | ~$GA.GoogleCanceled() => true
  | ~$GA.GoogleToken(token, account) => let
      val () = $BD.blob_free(token)
    in case+ account of ~$R.some(a) => let val () = $BD.blob_free(a) in false end | ~$R.none() => false end
  | ~$GA.GoogleNoAccount() => false
  | ~$GA.GoogleRefused() => false
  | ~$GA.GoogleUnavailable() => false

(* In a browser (no Capacitor): the token through Google Identity
   Services, which check.mjs plays: a token asks again, a cancel signs
   out (revoking the token given), so its log shows each answer *)
implement main0 () =
  if ~$GA.google_token_available() then ()
  else let
    val first = $P.and_then<$GA.google_token><$GA.google_token>(ask(), llam(answer) =>
      if is_token(answer) then ask() else $P.ret<$GA.google_token>($GA.GoogleRefused()))
  in
    $P.finish<$GA.google_token>(first, llam(answer) =>
      if is_canceled(answer) then $P.finish<$GA.google_signed_out>($GA.google_sign_out(), llam(_) => ())
      else ())
  end
