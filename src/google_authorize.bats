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
   AuthorizeUnavailable or ChangeUnavailable (Capacitor's own code for a
   method a platform lacks, UNIMPLEMENTED).

   Every answer is an outcome of its own (bats-lang/quire#334): a
   refusal Play services names (a google_status, with its message), a
   cancel only for authorizeScopes' CANCELED (the reader backing out,
   or a CANCELED status Play services gives before any consent screen,
   which the plugin cannot tell apart: bats-lang/capacitor-plugins#8;
   its message is kept; CANCELED from any other call is a refusal), and
   anything this module does
   not recognise (the plugin's UNEXPECTED, a code it does not document,
   an answer missing what it must hold, a grant the types here cannot
   carry) AuthorizeUnexpected or
   ChangeUnexpected, with the code and the message as they came, never
   folded into a known outcome.

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

(* A refusal Play services documents: a status CommonStatusCodes names
   (getStatusCodeString, play-services-basement 18.9.0, which the
   plugin's play-services-auth 21.5.0 brings), decoded once
   from the plugin's code. SUCCESS and SUCCESS_CACHE are not refusals:
   a code naming them is unexpected *)
#pub datatype google_status =
  | StatusServiceVersionUpdateRequired | StatusServiceDisabled | StatusSignInRequired
  | StatusInvalidAccount | StatusResolutionRequired | StatusNetworkError | StatusInternalError
  | StatusDeveloperError | StatusError | StatusInterrupted | StatusTimeout | StatusCanceled
  | StatusApiNotConnected | StatusDeadClient | StatusRemoteException
  | StatusConnectionSuspendedDuringCall | StatusReconnectionTimedOutDuringUpdate
  | StatusReconnectionTimedOut

(* A status's name, as CommonStatusCodes gives it (DEVELOPER_ERROR) *)
#pub fn google_status_name (status: google_status): [n:pos | n < 64] string n

(* A status's number in CommonStatusCodes (DEVELOPER_ERROR is 10) *)
#pub fn google_status_number (status: google_status): [n:nat | n < 100] int n

(* What asking for an authorization came to. JS's answer is decoded
   here, once. Linear: its blobs are JS's until they are freed; an
   answer no consumer takes is freed by promise's dispose. *)
#pub datavtype google_authorization(asking) =
  (* The access token; the scopes granted, separated by spaces (at
     least one: a grant of none is unexpected; each a scope-token, of
     any length, so one of 256 bytes or more fits no google_scope); and
     the account the grant is for (an email address on Android), when
     the answer names one *)
  | {w:asking} Authorized(w) of
      ([n:pos] dblob(n), [k:pos] dblob(k), $R.option([a:pos] dblob(a)))
  (* The reader must consent first, and nothing was shown *)
  | NotAuthorized(Silently)
  (* The reader backed out of the consent screen (Google's result said
     so, or the screen ended with RESULT_CANCELED and returned nothing;
     one that returned nothing with any other result code is
     AuthorizeUnexpected): authorizeScopes' CANCELED. A CANCELED status
     Play services gives before any consent screen has the same code
     and reaches here too, as the plugin cannot tell it apart
     (bats-lang/capacitor-plugins#8): the message, when there is one,
     is the only thing that tells them apart, and is kept *)
  | AuthorizeCanceled(MayAsk) of $R.option([m:pos] dblob(m))
  (* Another call's consent screen was showing (CONSENT_SHOWING) *)
  | ConsentShowing(MayAsk)
  (* Play services refused, with its status and its message, when it
     gave one: any status CommonStatusCodes names, but CANCELED from
     authorizeScopes (AuthorizeCanceled); CANCELED from
     authorizationForScopes, which shows nothing to cancel, is one *)
  | {w:asking} AuthorizeRefused(w) of (google_status, $R.option([m:pos] dblob(m)))
  (* No plugin: a browser, or an app without it (UNIMPLEMENTED) *)
  | {w:asking} AuthorizeUnavailable(w)
  (* An answer this module does not recognise, with the code and the
     message as they came (each none when there was none, or it was
     empty), and only these: the
     plugin's UNEXPECTED; a rejection with no code; a code Play services
     names that is no refusal (SUCCESS, SUCCESS_CACHE), or a code
     neither Play services nor the plugin names; the plugin's INVALID_OPTIONS, which google_scopes' type
     keeps a call from earning; CONSENT_SHOWING from
     authorizationForScopes, which shows no consent screen. And, JS
     saying which it was, each in a message of its own (blank as the
     plugin's Java has it, String.isBlank): an answer the plugin does
     not document (one that is null or not an object, an empty one, an
     authorization that is not an object, or a null authorization from
     authorizeScopes; an access token missing,
     not a string, empty or blank; granted scopes that are not a
     non-empty list, or one that is not a string, is empty or is blank;
     an account missing from the answer, not a string, empty or blank;
     a rejection that is not an object whose code and message are each
     well-formed text or absent: one with no value, null, a string, an
     error whose code or message is a number or holds a lone
     surrogate); or a grant the plugin passes on that bridge does
     not take: a granted scope, not blank, that is not RFC 6749's
     scope-token (bats-lang/capacitor-plugins#9), or an access token or
     an account that starts with a byte order mark (U+FEFF, which JS's
     decoder would drop), is not well-formed Unicode (a lone surrogate),
     is over 4096 bytes or holds no visible ASCII character (0x21 to 0x7E),
     which google_text cannot carry (google_text_of's tests and bound,
     so a token Authorized gives can always be cleared as it came, and
     an account it names revoked; Google's access tokens are at most
     2048 bytes) *)
  | {w:asking} AuthorizeUnexpected(w) of ($R.option([c:pos] dblob(c)), $R.option([m:pos] dblob(m)))

(* How clearing a token or revoking a grant ended *)
#pub datavtype google_authorization_change =
  (* Cleared, or taken back *)
  | Changed
  (* Play services refused, with its status (any CommonStatusCodes
     names, CANCELED among them: neither call shows anything for the
     reader to cancel) and its message, when it gave one *)
  | ChangeRefused of (google_status, $R.option([m:pos] dblob(m)))
  (* No plugin: a browser, or an app without it (UNIMPLEMENTED) *)
  | ChangeUnavailable
  (* An answer this module does not recognise, with the code and the
     message as they came (each none when there was none, or it was
     empty), and only these: the
     plugin's UNEXPECTED; a rejection with no code; a code Play services
     names that is no refusal (SUCCESS, SUCCESS_CACHE), or a code
     neither Play services nor the plugin names; the
     plugin's INVALID_OPTIONS, which google_text's and google_scopes'
     types keep a call from earning; CONSENT_SHOWING, which neither call
     documents; and, JS saying what it was, a rejection that is not an
     object whose code and message are each well-formed text or absent
     (one with no value, null, a string, an error whose code or message
     is a number or holds a lone surrogate) *)
  | ChangeUnexpected of ($R.option([c:pos] dblob(c)), $R.option([m:pos] dblob(m)))

(* Whether the app has the plugin: false in a browser *)
#pub fun google_authorize_available(): bool

(* An OAuth scope: its text proven not empty by its type and checked to
   be RFC 6749's scope-token (NQCHAR bytes only, 0x21, 0x23 to 0x5B and
   0x5D to 0x7E: no whitespace or other control character, no DEL, no
   quote or backslash, nothing non-ASCII; the scopes of a call cross as one
   text, separated by spaces, RFC 6749 3.3), once, by google_scope_of,
   the only way to make one, so no call asks for an empty or blank
   scope, or splits one in two (quire#334). Under 256 bytes: a granted
   scope (Authorized's) may be longer, and then fits none. The set of scopes is open:
   one Google does not recognise is sent on, and what Google answers
   for it is not documented (it may be any outcome above) *)
#pub abstype google_scope = ptr

(* text as a scope, when it is RFC 6749's scope-token (NQCHAR bytes:
   0x21, 0x23 to 0x5B, 0x5D to 0x7E), so it holds no whitespace or
   other control character, no DEL, no quote or backslash and nothing
   non-ASCII *)
#pub fn google_scope_of {n:pos | n < 256} (text: string n): $R.option(google_scope)

(* A scope's text *)
#pub fn google_scope_text (scope: google_scope): [n:pos | n < 256] string n

(* The scopes of a call: k of them (at most 8 a call), at least one by
   construction, so the scopes a call sends are never empty *)
#pub datavtype google_scopes(int) =
  | OneScope(1) of google_scope
  | {k:pos} MoreScopes(k + 1) of (google_scope, google_scopes(k))

(* The access token for scopes when they are already granted, showing
   nothing: authorizationForScopes *)
#pub fun google_authorization_for_scopes
  {k:pos | k <= 8}
  (scopes: google_scopes(k))
  : $P.promise(google_authorization(Silently), $P.Chained)

(* The access token for scopes, showing Google's consent screen when
   the reader must consent first: authorizeScopes *)
#pub fun google_authorize_scopes
  {k:pos | k <= 8}
  (scopes: google_scopes(k))
  : $P.promise(google_authorization(MayAsk), $P.Chained)

(* A token or an account to hand Google: well-formed UTF-8 that does
   not start with a byte order mark (so JS reads it as it is, with
   nothing replaced or dropped) holding at least one visible
   ASCII character (0x21 to 0x7E), so never empty or blank (what the
   plugin refuses as INVALID_OPTIONS), checked once by google_text_of,
   the only way to make one, which copies them *)
#pub absvtype google_text = ptr

(* bytes[0, n) as a google_text, when they are well-formed UTF-8, do
   not start with a byte order mark (EF BB BF) and hold a visible ASCII
   character. At most 4096 bytes: Google's access tokens are at most
   2048, and an account is an email address *)
#pub fn google_text_of {l:agz}{n:pos | n <= 4096} (bytes: !$A.borrow(byte, l, n), n: int n): $R.option(google_text)

(* A google_text no call took *)
#pub fn google_text_free (text: google_text): void

(* Takes the access token out of Play services' cache:
   clearAuthorizationToken *)
#pub fun google_clear_token (token: google_text)
  : $P.promise(google_authorization_change, $P.Chained)

(* Takes back the account's grant of scopes (an Authorized answer's
   account): revokeAccess *)
#pub fun google_revoke_access
  {k:pos | k <= 8}
  (account: google_text, scopes: google_scopes(k))
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
   the scopes granted, the account, the platform's code and message *)
datatype answer_part = PartScopes | PartAccount | PartCode | PartMessage

fn _part_number (part: answer_part): int =
  case+ part of
  | PartScopes() => 0
  | PartAccount() => 1
  | PartCode() => 2
  | PartMessage() => 3

fn _part (resolver_id: int, part: answer_part): $R.option([n:pos] dblob(n)) =
  _nonempty(_bats_js_google_authorize_part(resolver_id, _part_number(part)))

implement google_status_name (status) =
  case+ status of
  | StatusServiceVersionUpdateRequired() => "SERVICE_VERSION_UPDATE_REQUIRED"
  | StatusServiceDisabled() => "SERVICE_DISABLED"
  | StatusSignInRequired() => "SIGN_IN_REQUIRED"
  | StatusInvalidAccount() => "INVALID_ACCOUNT"
  | StatusResolutionRequired() => "RESOLUTION_REQUIRED"
  | StatusNetworkError() => "NETWORK_ERROR"
  | StatusInternalError() => "INTERNAL_ERROR"
  | StatusDeveloperError() => "DEVELOPER_ERROR"
  | StatusError() => "ERROR"
  | StatusInterrupted() => "INTERRUPTED"
  | StatusTimeout() => "TIMEOUT"
  | StatusCanceled() => "CANCELED"
  | StatusApiNotConnected() => "API_NOT_CONNECTED"
  | StatusDeadClient() => "DEAD_CLIENT"
  | StatusRemoteException() => "REMOTE_EXCEPTION"
  | StatusConnectionSuspendedDuringCall() => "CONNECTION_SUSPENDED_DURING_CALL"
  | StatusReconnectionTimedOutDuringUpdate() => "RECONNECTION_TIMED_OUT_DURING_UPDATE"
  | StatusReconnectionTimedOut() => "RECONNECTION_TIMED_OUT"

implement google_status_number (status) =
  case+ status of
  | StatusServiceVersionUpdateRequired() => 2
  | StatusServiceDisabled() => 3
  | StatusSignInRequired() => 4
  | StatusInvalidAccount() => 5
  | StatusResolutionRequired() => 6
  | StatusNetworkError() => 7
  | StatusInternalError() => 8
  | StatusDeveloperError() => 10
  | StatusError() => 13
  | StatusInterrupted() => 14
  | StatusTimeout() => 15
  | StatusCanceled() => 16
  | StatusApiNotConnected() => 17
  | StatusDeadClient() => 18
  | StatusRemoteException() => 19
  | StatusConnectionSuspendedDuringCall() => 20
  | StatusReconnectionTimedOutDuringUpdate() => 21
  | StatusReconnectionTimedOut() => 22

(* The status after status, in the order the decoder tries them *)
fn _status_after (status: google_status): $R.option(google_status) =
  case+ status of
  | StatusServiceVersionUpdateRequired() => $R.some(StatusServiceDisabled())
  | StatusServiceDisabled() => $R.some(StatusSignInRequired())
  | StatusSignInRequired() => $R.some(StatusInvalidAccount())
  | StatusInvalidAccount() => $R.some(StatusResolutionRequired())
  | StatusResolutionRequired() => $R.some(StatusNetworkError())
  | StatusNetworkError() => $R.some(StatusInternalError())
  | StatusInternalError() => $R.some(StatusDeveloperError())
  | StatusDeveloperError() => $R.some(StatusError())
  | StatusError() => $R.some(StatusInterrupted())
  | StatusInterrupted() => $R.some(StatusTimeout())
  | StatusTimeout() => $R.some(StatusCanceled())
  | StatusCanceled() => $R.some(StatusApiNotConnected())
  | StatusApiNotConnected() => $R.some(StatusDeadClient())
  | StatusDeadClient() => $R.some(StatusRemoteException())
  | StatusRemoteException() => $R.some(StatusConnectionSuspendedDuringCall())
  | StatusConnectionSuspendedDuringCall() => $R.some(StatusReconnectionTimedOutDuringUpdate())
  | StatusReconnectionTimedOutDuringUpdate() => $R.some(StatusReconnectionTimedOut())
  | StatusReconnectionTimedOut() => $R.none()

(* Whether blob's bytes, from at on, are name's, from at on *)
fun _same {k:pos}{at:nat | at <= k} .<k - at>.
  (blob: !dblob(k), name: string k, n: int k, at: int at): bool =
  if at >= n then true
  else let
    val byte = $A.alloc<byte>(1)
    val () = blob_read(blob, at, byte, 1)
    val read = byte2int0($A.get<byte>(byte, 0))
    val () = $A.free<byte>(byte)
  in
    if read <> char2int0(string_get_at(name, at)) then false
    else _same(blob, name, n, at + 1)
  end

(* Whether code's bytes are exactly status's name *)
fn _named {k:pos} (code: !dblob(k), status: google_status): bool = let
  val name = google_status_name(status)
  val n = g1u2i(string1_length(name))
in if blob_len(code) <> n then false else _same(code, name, n, 0) end

(* The status code names: the first of status and those after it (fuel
   of them at most), or none *)
fun _status_from {k:pos}{fuel:nat} .<fuel>.
  (code: !dblob(k), status: google_status, fuel: int fuel): $R.option(google_status) =
  if _named(code, status) then $R.some(status)
  else if fuel <= 0 then $R.none()
  else case+ _status_after(status) of
    | ~$R.some(next) => _status_from(code, next, fuel - 1)
    | ~$R.none() => $R.none()

(* Whether code's bytes are exactly text *)
fn _is {k:pos}{n:pos} (code: !dblob(k), text: string n): bool = let
  val n = g1u2i(string1_length(text))
in if blob_len(code) <> n then false else _same(code, text, n, 0) end

(* A failure's code, decoded once: one of Play services' statuses
   (CANCELED among them, which is also the plugin's own code for a
   cancel: _asked tells the calls apart), the plugin's CONSENT_SHOWING,
   Capacitor's UNIMPLEMENTED (no plugin), or anything else (UNEXPECTED,
   INVALID_OPTIONS, SUCCESS, a code nothing documents, none) *)
datavtype failure =
  | FailedStatus of (google_status, $R.option([m:pos] dblob(m)))
  | {c:pos} FailedConsentShowing of (dblob(c), $R.option([m:pos] dblob(m)))
  | FailedUnavailable
  | FailedOther of ($R.option([c:pos] dblob(c)), $R.option([m:pos] dblob(m)))

fn _failure (code: $R.option([c:pos] dblob(c)), message: $R.option([m:pos] dblob(m))): failure =
  case+ code of
  | ~$R.none() => FailedOther($R.none(), message)
  | ~$R.some(blob) =>
    if _is(blob, "CONSENT_SHOWING") then FailedConsentShowing(blob, message)
    else if _is(blob, "UNIMPLEMENTED") then let
      val () = blob_free(blob)
      val () = _free_part(message)
    in FailedUnavailable() end
    else (case+ _status_from(blob, StatusServiceVersionUpdateRequired(), 18) of
      | ~$R.some(status) => let val () = blob_free(blob) in FailedStatus(status, message) end
      | ~$R.none() => FailedOther($R.some(blob), message))

(* JS's answer, before it is one of an atom's: the codes are the
   token's blob (positive), 0 not authorized, anything else failed. Every part is taken, whatever the code, so JS keeps
   none *)
datavtype answer =
  | AnswerToken of
      ([n:pos] dblob(n), [k:pos] dblob(k), $R.option([a:pos] dblob(a)))
  | AnswerNone
  | AnswerFailed of failure

fn _answer (resolver_id: int, code: Int): answer = let
  val scopes = _part(resolver_id, PartScopes())
  val account = _part(resolver_id, PartAccount())
  val failure = _part(resolver_id, PartCode())
  val message = _part(resolver_id, PartMessage())
in
  if code > 0 then
    (case+ _nonempty(code) of
     | ~$R.some(token) => (case+ scopes of
       | ~$R.some(granted) => let
           val () = _free_part(failure)
           val () = _free_part(message)
         in AnswerToken(token, granted, account) end
       (* JS answers a grant of no scope as failed, so a token comes with
          scopes; one without is an answer this module does not document *)
       | ~$R.none() => let
           val () = blob_free(token)
           val () = _free_part(account)
         in AnswerFailed(_failure(failure, message)) end)
     | ~$R.none() => let
         val () = _free_part(scopes)
         val () = _free_part(account)
       in AnswerFailed(_failure(failure, message)) end)
  else let
    val () = _free_part(scopes)
    val () = _free_part(account)
  in
    if code = 0 then let
      val () = _free_part(failure)
      val () = _free_part(message)
    in AnswerNone() end
    else AnswerFailed(_failure(failure, message))
  end
end

(* A failure of authorizationForScopes: it shows no consent screen, so
   CONSENT_SHOWING is a code it does not document *)
fn _found_failure (failure: failure): google_authorization(Silently) =
  case+ failure of
  | ~FailedStatus(status, message) => AuthorizeRefused(status, message)
  | ~FailedConsentShowing(code, message) => AuthorizeUnexpected($R.some(code), message)
  | ~FailedUnavailable() => AuthorizeUnavailable()
  | ~FailedOther(code, message) => AuthorizeUnexpected(code, message)

(* authorizationForScopes' answer: Play services' CANCELED from it
   (it shows nothing to cancel) is a refusal like any other status *)
fn _found (answer: answer): google_authorization(Silently) =
  case+ answer of
  | ~AnswerToken(token, scopes, account) => Authorized(token, scopes, account)
  | ~AnswerNone() => NotAuthorized()
  | ~AnswerFailed(failure) => _found_failure(failure)

(* authorizeScopes' answer: it always gives an authorization when it
   resolves (JS answers 0 only for authorizationForScopes), so none is
   unexpected; CANCELED, decoded here alone, is AuthorizeCanceled with
   its message: the plugin's code for the reader backing out, which a
   CANCELED status Play services gives before any consent screen shares
   (bats-lang/capacitor-plugins#8) *)
fn _asked (answer: answer): google_authorization(MayAsk) =
  case+ answer of
  | ~AnswerToken(token, scopes, account) => Authorized(token, scopes, account)
  | ~AnswerNone() => AuthorizeUnexpected($R.none(), $R.none())
  | ~AnswerFailed(failure) => (case+ failure of
    | ~FailedStatus(status, message) => (case+ status of
      | StatusCanceled() => AuthorizeCanceled(message)
      | _ =>> AuthorizeRefused(status, message))
    | ~FailedConsentShowing(code, message) => let
        val () = blob_free(code)
        val () = _free_part(message)
      in ConsentShowing() end
    | ~FailedUnavailable() => AuthorizeUnavailable()
    | ~FailedOther(code, message) => AuthorizeUnexpected(code, message))

(* clearAuthorizationToken's and revokeAccess': 0 done, anything else
   failed; neither shows a consent screen *)
fn _change (resolver_id: int, code: Int): google_authorization_change = let
  val failure = _part(resolver_id, PartCode())
  val message = _part(resolver_id, PartMessage())
in
  if code = 0 then let
    val () = _free_part(failure)
    val () = _free_part(message)
  in Changed() end
  else (case+ _failure(failure, message) of
    | ~FailedStatus(status, message) => ChangeRefused(status, message)
    | ~FailedConsentShowing(code, message) => ChangeUnexpected($R.some(code), message)
    | ~FailedUnavailable() => ChangeUnavailable()
    | ~FailedOther(code, message) => ChangeUnexpected(code, message))
end

fn {} _free_authorization {w:asking} (answer: google_authorization(w)): void =
  case+ answer of
  | ~Authorized(token, scopes, account) => let
      val () = blob_free(token)
      val () = blob_free(scopes)
    in _free_part(account) end
  | ~NotAuthorized() => ()
  | ~AuthorizeCanceled(message) => _free_part(message)
  | ~ConsentShowing() => ()
  | ~AuthorizeRefused(_, message) => _free_part(message)
  | ~AuthorizeUnavailable() => ()
  | ~AuthorizeUnexpected(code, message) => let
      val () = _free_part(code)
    in _free_part(message) end

(* Answers nobody took: their blobs are freed. Before their first use *)
implement $P.dispose<google_authorization(Silently)>(answer) = _free_authorization(answer)
implement $P.dispose<google_authorization(MayAsk)>(answer) = _free_authorization(answer)
implement $P.dispose<google_authorization_change>(change) =
  case+ change of
  | ~Changed() => ()
  | ~ChangeRefused(_, message) => _free_part(message)
  | ~ChangeUnavailable() => ()
  | ~ChangeUnexpected(code, message) => let
      val () = _free_part(code)
    in _free_part(message) end

implement google_authorize_available() = _bats_js_google_authorize_available() > 0

$UNSAFE begin
assume google_scope = [n:pos | n < 256] string n
end

(* Whether text[at, n) is a scope-token: RFC 6749's NQCHAR bytes only *)
fun _no_space {n:pos}{at:nat | at <= n} .<n - at>. (text: string n, n: int n, at: int at): bool =
  if at >= n then true
  else let
    val c = char2int0(string_get_at(text, at))
  in
    (* RFC 6749's scope-token: NQCHAR, 0x21, 0x23 to 0x5B, 0x5D to
       0x7E; no whitespace of any kind, and nothing non-ASCII *)
    if c = 0x21 then _no_space(text, n, at + 1)
    else if c >= 0x23 && c <= 0x5B then _no_space(text, n, at + 1)
    else if c >= 0x5D && c <= 0x7E then _no_space(text, n, at + 1)
    else false
  end

implement google_scope_of (text) = let
  val n = g1u2i(string1_length(text))
in if _no_space(text, n, 0) then $R.some(text) else $R.none() end

implement google_scope_text (scope) = scope

(* The bytes scopes are written into: 8 of them at most, each under
   256 bytes and a space *)
#define SCOPES_BYTES 2048

(* scopes' texts, separated by spaces (RFC 6749, 3.3), at out[at];
   where they end. The scopes are consumed *)
fun _scopes_put {l:agz}{k:pos}{at:nat | at + k * 256 <= SCOPES_BYTES} .<k>.
  (scopes: google_scopes(k), out: !$A.arr(byte, l, SCOPES_BYTES), at: int at)
  : [stop:nat | at < stop; stop <= at + k * 256] int stop =
  case+ scopes of
  | ~OneScope(scope) => let
      val text = google_scope_text(scope)
      val n = g1u2i(string1_length(text))
      val () = $A.write_text(out, at, $A.text_lit(text), n)
    in at + n end
  | ~MoreScopes(scope, rest) => let
      val text = google_scope_text(scope)
      val n = g1u2i(string1_length(text))
      val () = $A.write_text(out, at, $A.text_lit(text), n)
      val () = $A.write_byte(out, at + n, 32)
    in _scopes_put(rest, out, at + n + 1) end

(* Asks JS, may_ask 0 for authorizationForScopes and 1 for
   authorizeScopes; resolves with the resolver's id and JS's code *)
fn _ask {k:pos | k <= 8} (scopes: google_scopes(k), may_ask: int)
  : @(int, $P.promise(Int, $P.Pending)) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val out = $A.alloc<byte>(SCOPES_BYTES)
  val stop = _scopes_put(scopes, out, 0)
  val @(frozen, borrowed) = $A.freeze<byte>(out)
  val () = _bats_js_google_authorize(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(borrowed) end, stop, may_ask, id)
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in @(id, p) end

implement google_authorization_for_scopes{k}(scopes) = let
  val @(id, p) = _ask(scopes, 0)
in $P.and_then<Int><google_authorization(Silently)>(p, llam (code) =>
  $P.ret<google_authorization(Silently)>(_found(_answer(id, code)))) end

implement google_authorize_scopes{k}(scopes) = let
  val @(id, p) = _ask(scopes, 1)
in $P.and_then<Int><google_authorization(MayAsk)>(p, llam (code) =>
  $P.ret<google_authorization(MayAsk)>(_asked(_answer(id, code)))) end

datavtype text_rep = {l:agz}{n:pos} TextRep of ($A.arr(byte, l, n), int n)
$UNSAFE begin
assume google_text = text_rep
end

(* Whether bytes[at, n) hold a visible ASCII character *)
fun _visible {l:agz}{n:pos}{at:nat | at <= n} .<n - at>. (bytes: !$A.borrow(byte, l, n), n: int n, at: int at): bool =
  if at >= n then false
  else let
    val c = byte2int0($A.read<byte>(bytes, at))
  in if c >= 0x21 && c <= 0x7E then true else _visible(bytes, n, at + 1) end

(* Whether bytes[i] is from lo to hi *)
fn _in {l:agz}{n:pos}{i:nat | i < n} (bytes: !$A.borrow(byte, l, n), i: int i, lo: int, hi: int): bool = let
  val c = byte2int0($A.read<byte>(bytes, i))
in c >= lo && c <= hi end

(* Whether bytes[at, n) are well-formed UTF-8 (RFC 3629, 4: no overlong
   form, no surrogate, nothing over U+10FFFF), so JS reads them as they
   are, with nothing replaced *)
fun _utf8 {l:agz}{n:pos}{at:nat | at <= n} .<n - at>. (bytes: !$A.borrow(byte, l, n), n: int n, at: int at): bool =
  if at >= n then true
  else let
    val c = byte2int0($A.read<byte>(bytes, at))
  in
    if c < 0x80 then _utf8(bytes, n, at + 1)
    else if c < 0xC2 then false
    else if c < 0xE0 then
      (if at + 1 < n then
        (if _in(bytes, at + 1, 0x80, 0xBF) then _utf8(bytes, n, at + 2) else false)
      else false)
    else if c < 0xF0 then
      (if at + 2 < n then let
        val lo = (if c = 0xE0 then 0xA0 else 0x80): int
        val hi = (if c = 0xED then 0x9F else 0xBF): int
      in
        if _in(bytes, at + 1, lo, hi) then
          (if _in(bytes, at + 2, 0x80, 0xBF) then _utf8(bytes, n, at + 3) else false)
        else false
      end
      else false)
    else if c < 0xF5 then
      (if at + 3 < n then let
        val lo = (if c = 0xF0 then 0x90 else 0x80): int
        val hi = (if c = 0xF4 then 0x8F else 0xBF): int
      in
        if _in(bytes, at + 1, lo, hi) then
          (if _in(bytes, at + 2, 0x80, 0xBF) then
            (if _in(bytes, at + 3, 0x80, 0xBF) then _utf8(bytes, n, at + 4) else false)
          else false)
        else false
      end
      else false)
    else false
  end

(* Whether bytes[0, n) start with a byte order mark (EF BB BF), which
   JS's TextDecoder drops *)
fn _byte_order_mark {l:agz}{n:pos} (bytes: !$A.borrow(byte, l, n), n: int n): bool =
  if n < 3 then false
  else if _in(bytes, 0, 0xEF, 0xEF) then
    (if _in(bytes, 1, 0xBB, 0xBB) then _in(bytes, 2, 0xBF, 0xBF) else false)
  else false

implement google_text_of {l}{n} (bytes, n) =
  if ~_visible(bytes, n, 0) then $R.none()
  else if ~_utf8(bytes, n, 0) then $R.none()
  else if _byte_order_mark(bytes, n) then $R.none()
  else let
    val copy = $A.alloc<byte>(n)
    val () = $A.write_borrow(copy, 0, bytes, n)
  in $R.some(TextRep(copy, n)) end

implement google_text_free (text) =
  case+ text of ~TextRep(bytes, _) => $A.free<byte>(bytes)

implement google_clear_token(token) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val ~TextRep(bytes, n) = token
  val @(frozen, borrowed) = $A.freeze<byte>(bytes)
  val () = _bats_js_google_clear_token(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(borrowed) end, n, id)
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in $P.and_then<Int><google_authorization_change>(p, llam (code) =>
  $P.ret<google_authorization_change>(_change(id, code))) end

implement google_revoke_access{k}(account, scopes) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val out = $A.alloc<byte>(SCOPES_BYTES)
  val stop = _scopes_put(scopes, out, 0)
  val @(frozen, borrowed) = $A.freeze<byte>(out)
  val ~TextRep(account_bytes, account_len) = account
  val @(account_frozen, account_borrowed) = $A.freeze<byte>(account_bytes)
  val () = _bats_js_google_revoke_access(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(account_borrowed) end, account_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(borrowed) end, stop, id)
  val () = $A.drop<byte>(account_frozen, account_borrowed)
  val () = $A.free<byte>($A.thaw<byte>(account_frozen))
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in $P.and_then<Int><google_authorization_change>(p, llam (code) =>
  $P.ret<google_authorization_change>(_change(id, code))) end

end (* #target wasm *)
