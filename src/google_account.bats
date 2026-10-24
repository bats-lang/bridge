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

(* What asking for a token came to, each outcome its own. JS's answer is
   decoded here, once: the token (and the account's address, when Google
   gave one), the reader closing the window, Google answering with no token
   (its answer, as text), no way to ask here, the sign-in script not loading
   (what, as text), the request rejected or thrown (what, as text), an
   answer that could not be read or written down (what, as text), and a code
   JS never gives. The text is none when JS could not write it down. Linear
   (the blobs), so the one consumer takes it apart with case+ ~; one no
   consumer takes is freed by promise's dispose. *)
#pub datavtype token_answer =
  | TokenGiven of ([n:pos] dblob(n), $R.option([k:pos] dblob(k)))   (* the access token, and the account's address *)
  | TokenCanceled                                                   (* the reader closed Google's window or said no *)
  | TokenRefused of $R.option([n:nat] dblob(n))                     (* Google answered with no token: its answer, as text *)
  | TokenNotHere                                                    (* no way to ask here: the app, or a page with no document *)
  | TokenLoadFailed of $R.option([n:nat] dblob(n))                  (* the sign-in script did not load: what, as text *)
  | TokenThrown of $R.option([n:nat] dblob(n))                      (* the request was rejected or threw: what, as text *)
  | TokenAnswerUnread of $R.option([n:nat] dblob(n))                (* the answer could not be read or written down: what, as text *)
  | TokenUnexpected of Int                                          (* a code JS never gives *)

(* How signing out ended. Deprecated (google_account, bridge#231): it folds
   a script that did not load and a revoke that threw into
   GoogleSignOutFailed (and an unsuccessful revoke, an answer with no flag
   and a flag that throws into GoogleSignedOut); sign_out_answer tells them apart. *)
#pub datatype google_signed_out =
  | GoogleSignedOut
  | GoogleSignOutFailed

(* How signing out ended, each outcome its own. JS's answer is decoded
   here, once: the token revoked (or none to revoke), no way to revoke
   here, the revoke answered unsuccessful (its answer, as text), the
   sign-in script not loading (what, as text), the call rejected or thrown
   (what, as text), an answer that tells neither (as text), an answer whose
   flag could not be read (what, as text), and a code JS never gives. The text is none when JS could not write it down. Linear
   (the text), so the one consumer takes it apart with case+ ~; one no
   consumer takes is freed by promise's dispose. *)
#pub datavtype sign_out_answer =
  | SignOutDone                                           (* the token was revoked, or there was none *)
  | SignOutNotHere                                        (* no way to revoke here: the app, or a page with no document *)
  | SignOutRevokeFailed of $R.option([n:nat] dblob(n))    (* Google answered that the revoke was not successful: its answer, as text *)
  | SignOutLoadFailed of $R.option([n:nat] dblob(n))      (* the sign-in script did not load: what, as text *)
  | SignOutThrown of $R.option([n:nat] dblob(n))          (* the revoke was rejected or threw: what, as text *)
  | SignOutAnswerOdd of $R.option([n:nat] dblob(n))       (* the answer has no successful true or false: as text *)
  | SignOutAnswerUnread of $R.option([n:nat] dblob(n))    (* reading the answer's successful threw: what, as text *)
  | SignOutUnexpected of Int                              (* a code JS never gives *)

(* Whether a token can be asked for here: a browser (its sign-in script
   is then loaded, for the click that asks); never in the app *)
#pub fun google_token_available(): bool

(* An access token for scope[0, scope_len) (one OAuth scope, as
   https://www.googleapis.com/auth/drive.appdata), for the account the
   reader chooses in Google's window, through the web client
   client_id[0, client_len).
   Deprecated (google_account, bridge#235): google_token_get_answer. *)
#pub fun google_token_get
  {lc:agz}{nc:pos}{ls:agz}{ns:pos}
  (client_id: !$A.borrow(byte, lc, nc), client_len: int nc,
   scope: !$A.borrow(byte, ls, ns), scope_len: int ns)
  : $P.promise(google_token, $P.Chained)

(* google_token_get with every outcome its own *)
#pub fun google_token_get_answer
  {lc:agz}{nc:pos}{ls:agz}{ns:pos}
  (client_id: !$A.borrow(byte, lc, nc), client_len: int nc,
   scope: !$A.borrow(byte, ls, ns), scope_len: int ns)
  : $P.promise(token_answer, $P.Chained)

(* Revokes the token given, so the next token is asked for anew.
   Deprecated (google_account, bridge#231): google_sign_out_answer. *)
#pub fun google_sign_out(): $P.promise(google_signed_out, $P.Chained)

(* google_sign_out with every outcome its own *)
#pub fun google_sign_out_answer(): $P.promise(sign_out_answer, $P.Chained)

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
extern int bats_js_google_sign_out_text(int);
extern int bats_js_google_token_text(int);
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
extern fun _bats_js_google_sign_out_text
  (resolver_id: int): int = "mac#bats_js_google_sign_out_text"
extern fun _bats_js_google_token_text
  (resolver_id: int): int = "mac#bats_js_google_token_text"
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

(* What a request for a token was rejected with, threw or was answered, as
   text: JS kept it under the call's number, and none when it could not be
   written down *)
fn _token_text (resolver_id: int): $R.option([n:nat] dblob(n)) = let
  val handle = _bats_js_google_token_text(resolver_id)
in
  if handle <= 0 then $R.none() else _claimed(handle)
end

fn _free_token_text (text: $R.option([n:nat] dblob(n))): void =
  case+ text of ~$R.some(blob) => blob_free(blob) | ~$R.none() => ()

(* JS's codes: the token's blob (positive), -2 the reader closed the window,
   -3 Google answered with no token, -4 not here, -5 the script did not
   load, -6 rejected or threw, -7 the answer could not be read or written
   down (the text of -3, -5, -6 and -7 kept by the call's number); any other
   is a code JS never gives. The account's address is the blob JS kept for
   this request (bats_js_google_account), taken once *)
fn _token_answer (resolver_id: int, code: Int): token_answer = let
  val account = _nonempty(_bats_js_google_account(resolver_id))
in
  if code > 0 then
    (case+ _nonempty(code) of
     | ~$R.some(token) => TokenGiven(token, account)
     | ~$R.none() => let
         val () = (case+ account of ~$R.some(a) => blob_free(a) | ~$R.none() => ())
       in TokenUnexpected(code) end)
  else let
    val () = (case+ account of ~$R.some(a) => blob_free(a) | ~$R.none() => ())
  in
    if code = ~2 then TokenCanceled()
    else if code = ~3 then TokenRefused(_token_text(resolver_id))
    else if code = ~4 then TokenNotHere()
    else if code = ~5 then TokenLoadFailed(_token_text(resolver_id))
    else if code = ~6 then TokenThrown(_token_text(resolver_id))
    else if code = ~7 then TokenAnswerUnread(_token_text(resolver_id))
    else TokenUnexpected(code)
  end
end

(* An answer nobody took: its blobs are freed *)
implement $P.dispose<token_answer>(answer) =
  case+ answer of
  | ~TokenGiven(token, account) => let
      val () = blob_free(token)
    in case+ account of ~$R.some(a) => blob_free(a) | ~$R.none() => () end
  | ~TokenCanceled() => ()
  | ~TokenRefused(text) => _free_token_text(text)
  | ~TokenNotHere() => ()
  | ~TokenLoadFailed(text) => _free_token_text(text)
  | ~TokenThrown(text) => _free_token_text(text)
  | ~TokenAnswerUnread(text) => _free_token_text(text)
  | ~TokenUnexpected(_) => ()

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

implement google_token_get_answer{lc}{nc}{ls}{ns}(client_id, client_len, scope, scope_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_google_token(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(client_id) end, client_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(scope) end, scope_len, id)
in $P.and_then<Int><token_answer>(p, llam (code) =>
  $P.ret<token_answer>(_token_answer(id, code))) end

(* The old outcome, as it always was: the token; the reader closing the
   window is GoogleCanceled; no way here is GoogleUnavailable; Google
   answering with no token, the script not loading, the request rejected or
   thrown, an answer that could not be read and a code JS never gives were
   all GoogleRefused (the text freed). GoogleNoAccount is given by no
   platform. *)
fn _google_token (answer: token_answer): google_token =
  case+ answer of
  | ~TokenGiven(token, account) => GoogleToken(token, account)
  | ~TokenCanceled() => GoogleCanceled()
  | ~TokenRefused(text) => let val () = _free_token_text(text) in GoogleRefused() end
  | ~TokenNotHere() => GoogleUnavailable()
  | ~TokenLoadFailed(text) => let val () = _free_token_text(text) in GoogleRefused() end
  | ~TokenThrown(text) => let val () = _free_token_text(text) in GoogleRefused() end
  | ~TokenAnswerUnread(text) => let val () = _free_token_text(text) in GoogleRefused() end
  | ~TokenUnexpected(_) => GoogleRefused()

implement google_token_get{lc}{nc}{ls}{ns}(client_id, client_len, scope, scope_len) =
  $P.and_then<token_answer><google_token>(
    google_token_get_answer(client_id, client_len, scope, scope_len), llam (answer) =>
    $P.ret<google_token>(_google_token(answer)))

(* What the revoke rejected with, threw or answered, as text: JS kept it
   under the call's number, and none when it could not be written down *)
fn _sign_out_text (resolver_id: int): $R.option([n:nat] dblob(n)) = let
  val handle = _bats_js_google_sign_out_text(resolver_id)
in
  if handle <= 0 then $R.none() else _claimed(handle)
end

fn _free_sign_out_text (text: $R.option([n:nat] dblob(n))): void =
  case+ text of ~$R.some(blob) => blob_free(blob) | ~$R.none() => ()

(* JS's codes: 0 revoked or nothing to revoke, 1 no way here, -2 the revoke
   answered unsuccessful, -3 the script did not load, -4 rejected or threw,
   -5 an answer with no successful true or false, -6 reading the flag threw
   (the text of -2 to -6 kept by the call's number); any other is a code JS never gives *)
fn _sign_out_answer (code: Int, resolver_id: int): sign_out_answer =
  if code = 0 then SignOutDone()
  else if code = 1 then SignOutNotHere()
  else if code = ~2 then SignOutRevokeFailed(_sign_out_text(resolver_id))
  else if code = ~3 then SignOutLoadFailed(_sign_out_text(resolver_id))
  else if code = ~4 then SignOutThrown(_sign_out_text(resolver_id))
  else if code = ~5 then SignOutAnswerOdd(_sign_out_text(resolver_id))
  else if code = ~6 then SignOutAnswerUnread(_sign_out_text(resolver_id))
  else SignOutUnexpected(code)

(* An answer nobody took: its text freed *)
implement $P.dispose<sign_out_answer>(answer) =
  case+ answer of
  | ~SignOutDone() => ()
  | ~SignOutNotHere() => ()
  | ~SignOutRevokeFailed(text) => _free_sign_out_text(text)
  | ~SignOutLoadFailed(text) => _free_sign_out_text(text)
  | ~SignOutThrown(text) => _free_sign_out_text(text)
  | ~SignOutAnswerOdd(text) => _free_sign_out_text(text)
  | ~SignOutAnswerUnread(text) => _free_sign_out_text(text)
  | ~SignOutUnexpected(_) => ()

implement google_sign_out_answer() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_google_sign_out(id)
in $P.and_then<Int><sign_out_answer>(p, llam (code) =>
  $P.ret<sign_out_answer>(_sign_out_answer(code, id))) end

(* The old outcome, as it always was: signed out when the revoke was
   answered (successful or not, in a form with no flag, or with a flag that
   throws when read: the old JS never read the answer) or there was none to
   revoke; GoogleSignOutFailed for no way here, the script not loading and
   the revoke rejected or thrown (the text freed) *)
fn _signed_out (answer: sign_out_answer): google_signed_out =
  case+ answer of
  | ~SignOutDone() => GoogleSignedOut()
  | ~SignOutNotHere() => GoogleSignOutFailed()
  | ~SignOutRevokeFailed(text) => let val () = _free_sign_out_text(text) in GoogleSignedOut() end
  | ~SignOutLoadFailed(text) => let val () = _free_sign_out_text(text) in GoogleSignOutFailed() end
  | ~SignOutThrown(text) => let val () = _free_sign_out_text(text) in GoogleSignOutFailed() end
  | ~SignOutAnswerOdd(text) => let val () = _free_sign_out_text(text) in GoogleSignedOut() end
  | ~SignOutAnswerUnread(text) => let val () = _free_sign_out_text(text) in GoogleSignedOut() end
  | ~SignOutUnexpected(_) => GoogleSignOutFailed()

implement google_sign_out() =
  $P.and_then<sign_out_answer><google_signed_out>(google_sign_out_answer(), llam (answer) =>
    $P.ret<google_signed_out>(_signed_out(answer)))

end (* #target wasm *)
