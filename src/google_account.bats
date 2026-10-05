(* google_account -- an access token for the reader's Google account, in
   a browser

   Google Identity Services' token model (its script loaded from
   accounts.google.com when google_token_available is first asked, so a
   click's request opens Google's window at once): a token for about an
   hour, with no refresh token, as a page with no server gets; the
   account's address is not given. Signing out revokes the token given.

   The app has none of this: google_authorize.bats is its way (Play
   services' AuthorizationClient, with no sign-in). Capawesome's Google
   Sign-In, which this module used in the app, showed Credential
   Manager's sheet before each authorization and is gone from the
   plugin table (bats-lang/quire#321); in the app, google_token_available
   is false and google_token_get answers GoogleUnavailable. *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* What asking for a token came to. JS's answer is decoded here, once: a
   code it should not send is GoogleRefused. Linear: GoogleToken holds
   the token (and the account's address, when Google gave one) as blobs
   JS keeps until they are freed; one no consumer takes is freed by
   promise's dispose. *)
#pub datavtype google_token =
  (* The access token, and the account's address *)
  | GoogleToken of ([n:pos] dblob(n), $R.option([k:pos] dblob(k)))
  (* No Google account on the device: given by no platform since the
     app's plugin went (Google Identity Services lets the reader add
     one in its window); kept so that an app's match of it still
     stands *)
  | GoogleNoAccount
  (* The person said no *)
  | GoogleCanceled
  (* Google refused: the page's origin is not registered with the OAuth
     client, or it failed otherwise *)
  | GoogleRefused
  (* No way to ask here: the app, or a page with no document *)
  | GoogleUnavailable

(* How signing out ended *)
#pub datatype google_signed_out =
  | GoogleSignedOut
  | GoogleSignOutFailed

(* Whether a token can be asked for here: a browser (its sign-in script
   is then loaded, for the click that asks); never in the app *)
#pub fun google_token_available(): bool

(* An access token for scope[0, scope_len) (one OAuth scope, as
   https://www.googleapis.com/auth/drive.appdata), for the account the
   reader chooses in Google's window, through the web client
   client_id[0, client_len) *)
#pub fun google_token_get
  {lc:agz}{nc:pos}{ls:agz}{ns:pos}
  (client_id: !$A.borrow(byte, lc, nc), client_len: int nc,
   scope: !$A.borrow(byte, ls, ns), scope_len: int ns)
  : $P.promise(google_token, $P.Chained)

(* Revokes the token given, so the next token is asked for anew *)
#pub fun google_sign_out(): $P.promise(google_signed_out, $P.Chained)

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

$UNSAFE begin
%{
extern int bats_js_google_token_available(void);
extern void bats_js_google_token(void*, int, void*, int, int);
extern int bats_js_google_account(int);
extern void bats_js_google_sign_out(int);
%}
extern fun _bats_js_google_token_available
  (): int = "mac#bats_js_google_token_available"
extern fun _bats_js_google_token
  (client_id: ptr, client_len: int, scope: ptr, scope_len: int, resolver_id: int)
  : void = "mac#bats_js_google_token"
extern fun _bats_js_google_account
  (resolver_id: int): int = "mac#bats_js_google_account"
extern fun _bats_js_google_sign_out
  (resolver_id: int): void = "mac#bats_js_google_sign_out"
end

(* JS's code for a blob, as a handle: bridge's own atoms are the only
   ones that give one *)
fn _claimed (code: int): $R.option([n:nat] dblob(n)) =
  blob_claim($UNSAFE begin $UNSAFE.cast{blob_handle}(code) end)

(* A blob JS gave, when it is one and not empty *)
fn _nonempty (code: int): $R.option([n:pos] dblob(n)) =
  if code <= 0 then $R.none()
  else (case+ _claimed(code) of
    | ~$R.some(blob) =>
      if blob_len(blob) > 0 then $R.some(blob)
      else let val () = blob_free(blob) in $R.none() end
    | ~$R.none() => $R.none())

(* JS's codes: the token's blob (positive), -1 no account, -2 canceled,
   -4 not here, anything else refused. The account's address is the
   blob JS kept for this request (bats_js_google_account), taken once *)
fn _google_token (resolver_id: int, code: Int): google_token = let
  val account = _nonempty(_bats_js_google_account(resolver_id))
in
  if code > 0 then
    (case+ _nonempty(code) of
     | ~$R.some(token) => GoogleToken(token, account)
     | ~$R.none() => let
         val () = (case+ account of ~$R.some(a) => blob_free(a) | ~$R.none() => ())
       in GoogleRefused() end)
  else let
    val () = (case+ account of ~$R.some(a) => blob_free(a) | ~$R.none() => ())
  in
    if code = ~1 then GoogleNoAccount()
    else if code = ~2 then GoogleCanceled()
    else if code = ~4 then GoogleUnavailable()
    else GoogleRefused()
  end
end

(* An answer nobody took: its blobs are freed. Before google_token_get,
   its first use. *)
implement $P.dispose<google_token>(answer) =
  case+ answer of
  | ~GoogleToken(token, account) => let
      val () = blob_free(token)
    in case+ account of ~$R.some(a) => blob_free(a) | ~$R.none() => () end
  | ~GoogleNoAccount() => ()
  | ~GoogleCanceled() => ()
  | ~GoogleRefused() => ()
  | ~GoogleUnavailable() => ()

implement $P.dispose<google_signed_out>(_) = ()

implement google_token_available() = _bats_js_google_token_available() > 0

implement google_token_get{lc}{nc}{ls}{ns}(client_id, client_len, scope, scope_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_google_token(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(client_id) end, client_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(scope) end, scope_len, id)
in $P.and_then<Int><google_token>(p, llam (code) =>
  $P.ret<google_token>(_google_token(id, code))) end

implement google_sign_out() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_google_sign_out(id)
in $P.and_then<Int><google_signed_out>(p, llam (code) =>
  $P.ret<google_signed_out>(if code = 0 then GoogleSignedOut() else GoogleSignOutFailed())) end

end (* #target wasm *)
