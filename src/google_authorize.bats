(* google_authorize -- Google authorization with no sign-in, in the app

   App (Capacitor): the GoogleAuthorize plugin (plugins.bats,
   bats-lang/capacitor-plugins' google-authorize), over Play services'
   AuthorizationClient: an access token for OAuth scopes, for the
   account on the device that was granted them, with no sign-in sheet.
   Its calls are shaped as Flutter's google_sign_in 7.x
   GoogleSignInAuthorizationClient (bats-lang/quire#321), and each atom
   here is one of them:

   - google_authorization_for_scopes: authorizationForScopes, the token
     when the scopes are already granted, never showing anything;
   - google_authorize_scopes: authorizeScopes, the token, showing
     Google's consent screen when the reader must consent first;
   - google_clear_token: clearAuthorizationToken, a token Google
     refused taken out of Play services' cache, so the next
     authorization gets a new one;
   - google_revoke_access: revokeAccess, the account's grant taken
     back.

   Android only: a browser has no plugin (google_account.bats' Google
   Identity Services is the browser's way), and each atom then answers
   AuthorizeFailed or ChangeFailed with Capacitor's own code for a
   method a platform lacks, UNIMPLEMENTED.

   Scopes cross as OAuth writes a list of them, separated by spaces
   (RFC 6749, 3.3; a scope has no space in it): those asked for, and
   those granted. *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* How an authorization is asked for: Silently, never showing
   anything (authorizationForScopes), or MayAsk, showing Google's
   consent screen when the reader must consent first (authorizeScopes) *)
#pub datasort asking = Silently | MayAsk

(* What asking for an authorization came to. JS's answer is decoded
   here, once. Linear: its blobs are JS's until they are freed; an
   answer no consumer takes is freed by promise's dispose. *)
#pub datavtype google_authorization(asking) =
  (* The access token; the scopes granted, separated by spaces (none
     when the answer lists none); and the account the grant is for (an
     email address on Android), when the answer names one *)
  | {w:asking} Authorized(w) of
      ([n:pos] dblob(n), $R.option([k:pos] dblob(k)), $R.option([a:pos] dblob(a)))
  (* The reader must consent first, and nothing was shown *)
  | NotAuthorized(Silently)
  (* The reader backed out of the consent screen *)
  | AuthorizeCanceled(MayAsk)
  (* The platform refused, with its code (CommonStatusCodes' name, as
     NETWORK_ERROR; CONSENT_SHOWING while another call's consent screen
     is showing; INVALID_OPTIONS; UNIMPLEMENTED with no plugin), or
     none when it gave no code or its answer was not one the plugin
     documents *)
  | {w:asking} AuthorizeFailed(w) of $R.option([c:pos] dblob(c))

(* How clearing a token or revoking a grant ended *)
#pub datavtype google_authorization_change =
  | Changed
  (* The platform refused, with its code, as AuthorizeFailed's *)
  | ChangeFailed of $R.option([c:pos] dblob(c))

(* Whether the app has the plugin: false in a browser *)
#pub fun google_authorize_available(): bool

(* The access token for scopes[0, scopes_len) (OAuth scopes, separated
   by spaces, as https://www.googleapis.com/auth/drive.appdata) when
   they are already granted, showing nothing: authorizationForScopes *)
#pub fun google_authorization_for_scopes
  {l:agz}{n:pos}
  (scopes: !$A.borrow(byte, l, n), scopes_len: int n)
  : $P.promise(google_authorization(Silently), $P.Chained)

(* The access token for scopes[0, scopes_len), showing Google's consent
   screen when the reader must consent first: authorizeScopes *)
#pub fun google_authorize_scopes
  {l:agz}{n:pos}
  (scopes: !$A.borrow(byte, l, n), scopes_len: int n)
  : $P.promise(google_authorization(MayAsk), $P.Chained)

(* Takes the access token token[0, token_len) out of Play services'
   cache: clearAuthorizationToken *)
#pub fun google_clear_token
  {l:agz}{n:pos}
  (token: !$A.borrow(byte, l, n), token_len: int n)
  : $P.promise(google_authorization_change, $P.Chained)

(* Takes back account[0, account_len)'s grant of scopes[0, scopes_len)
   (an Authorized answer's account and scopes): revokeAccess *)
#pub fun google_revoke_access
  {la:agz}{na:pos}{ls:agz}{ns:pos}
  (account: !$A.borrow(byte, la, na), account_len: int na,
   scopes: !$A.borrow(byte, ls, ns), scopes_len: int ns)
  : $P.promise(google_authorization_change, $P.Chained)

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

$UNSAFE begin
%{
extern int bats_js_google_authorize_available(void);
extern void bats_js_google_authorize(void*, int, int, int);
extern int bats_js_google_authorize_part(int, int);
extern void bats_js_google_clear_token(void*, int, int);
extern void bats_js_google_revoke_access(void*, int, void*, int, int);
%}
extern fun _bats_js_google_authorize_available
  (): int = "mac#bats_js_google_authorize_available"
extern fun _bats_js_google_authorize
  (scopes: ptr, scopes_len: int, may_ask: int, resolver_id: int)
  : void = "mac#bats_js_google_authorize"
extern fun _bats_js_google_authorize_part
  (resolver_id: int, part: int): int = "mac#bats_js_google_authorize_part"
extern fun _bats_js_google_clear_token
  (token: ptr, token_len: int, resolver_id: int)
  : void = "mac#bats_js_google_clear_token"
extern fun _bats_js_google_revoke_access
  (account: ptr, account_len: int, scopes: ptr, scopes_len: int, resolver_id: int)
  : void = "mac#bats_js_google_revoke_access"
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

fn _free_part (part: $R.option([n:pos] dblob(n))): void =
  case+ part of ~$R.some(blob) => blob_free(blob) | ~$R.none() => ()

(* The parts of an answer JS kept for the request, each taken once:
   the scopes granted, the account, the platform's code *)
datatype answer_part = PartScopes | PartAccount | PartCode

fn _part_number (part: answer_part): int =
  case+ part of
  | PartScopes() => 0
  | PartAccount() => 1
  | PartCode() => 2

fn _part (resolver_id: int, part: answer_part): $R.option([n:pos] dblob(n)) =
  _nonempty(_bats_js_google_authorize_part(resolver_id, _part_number(part)))

(* JS's answer, before it is one of an atom's: the codes are the
   token's blob (positive), 0 not authorized, -1 canceled, anything
   else failed. Every part is taken, whatever the code, so JS keeps
   none *)
datavtype answer =
  | AnswerToken of
      ([n:pos] dblob(n), $R.option([k:pos] dblob(k)), $R.option([a:pos] dblob(a)))
  | AnswerNone
  | AnswerCanceled
  | AnswerFailed of $R.option([c:pos] dblob(c))

fn _answer (resolver_id: int, code: Int): answer = let
  val scopes = _part(resolver_id, PartScopes())
  val account = _part(resolver_id, PartAccount())
  val failure = _part(resolver_id, PartCode())
in
  if code > 0 then
    (case+ _nonempty(code) of
     | ~$R.some(token) => let
         val () = _free_part(failure)
       in AnswerToken(token, scopes, account) end
     | ~$R.none() => let
         val () = _free_part(scopes)
         val () = _free_part(account)
       in AnswerFailed(failure) end)
  else let
    val () = _free_part(scopes)
    val () = _free_part(account)
  in
    if code = 0 then let val () = _free_part(failure) in AnswerNone() end
    else if code = ~1 then let val () = _free_part(failure) in AnswerCanceled() end
    else AnswerFailed(failure)
  end
end

(* authorizationForScopes' answer: it is never canceled, so a cancel is
   an answer it does not document, with no code *)
fn _found (answer: answer): google_authorization(Silently) =
  case+ answer of
  | ~AnswerToken(token, scopes, account) => Authorized(token, scopes, account)
  | ~AnswerNone() => NotAuthorized()
  | ~AnswerCanceled() => AuthorizeFailed($R.none())
  | ~AnswerFailed(failure) => AuthorizeFailed(failure)

(* authorizeScopes' answer: it always gives an authorization when it
   resolves, so none is an answer it does not document, with no code *)
fn _asked (answer: answer): google_authorization(MayAsk) =
  case+ answer of
  | ~AnswerToken(token, scopes, account) => Authorized(token, scopes, account)
  | ~AnswerNone() => AuthorizeFailed($R.none())
  | ~AnswerCanceled() => AuthorizeCanceled()
  | ~AnswerFailed(failure) => AuthorizeFailed(failure)

(* clearAuthorizationToken's and revokeAccess': 0 done, anything else
   failed *)
fn _change (resolver_id: int, code: Int): google_authorization_change = let
  val failure = _part(resolver_id, PartCode())
in
  if code = 0 then let val () = _free_part(failure) in Changed() end
  else ChangeFailed(failure)
end

fn {} _free_authorization {w:asking} (answer: google_authorization(w)): void =
  case+ answer of
  | ~Authorized(token, scopes, account) => let
      val () = blob_free(token)
      val () = _free_part(scopes)
    in _free_part(account) end
  | ~NotAuthorized() => ()
  | ~AuthorizeCanceled() => ()
  | ~AuthorizeFailed(failure) => _free_part(failure)

(* Answers nobody took: their blobs are freed. Before their first use *)
implement $P.dispose<google_authorization(Silently)>(answer) = _free_authorization(answer)
implement $P.dispose<google_authorization(MayAsk)>(answer) = _free_authorization(answer)
implement $P.dispose<google_authorization_change>(change) =
  case+ change of
  | ~Changed() => ()
  | ~ChangeFailed(failure) => _free_part(failure)

implement google_authorize_available() = _bats_js_google_authorize_available() > 0

(* Asks JS, may_ask 0 for authorizationForScopes and 1 for
   authorizeScopes; resolves with the resolver's id and JS's code *)
fn _ask {l:agz}{n:pos}
  (scopes: !$A.borrow(byte, l, n), scopes_len: int n, may_ask: int)
  : @(int, $P.promise(Int, $P.Pending)) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_google_authorize(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(scopes) end, scopes_len, may_ask, id)
in @(id, p) end

implement google_authorization_for_scopes{l}{n}(scopes, scopes_len) = let
  val @(id, p) = _ask(scopes, scopes_len, 0)
in $P.and_then<Int><google_authorization(Silently)>(p, llam (code) =>
  $P.ret<google_authorization(Silently)>(_found(_answer(id, code)))) end

implement google_authorize_scopes{l}{n}(scopes, scopes_len) = let
  val @(id, p) = _ask(scopes, scopes_len, 1)
in $P.and_then<Int><google_authorization(MayAsk)>(p, llam (code) =>
  $P.ret<google_authorization(MayAsk)>(_asked(_answer(id, code)))) end

implement google_clear_token{l}{n}(token, token_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_google_clear_token(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(token) end, token_len, id)
in $P.and_then<Int><google_authorization_change>(p, llam (code) =>
  $P.ret<google_authorization_change>(_change(id, code))) end

implement google_revoke_access{la}{na}{ls}{ns}(account, account_len, scopes, scopes_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_google_revoke_access(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(account) end, account_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(scopes) end, scopes_len, id)
in $P.and_then<Int><google_authorization_change>(p, llam (code) =>
  $P.ret<google_authorization_change>(_change(id, code))) end

end (* #target wasm *)
