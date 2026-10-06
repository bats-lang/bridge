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
   AuthorizeUnavailable or ChangeUnavailable with nothing; where the
   plugin is there but the platform lacks the method, they carry the
   platform's UNIMPLEMENTED rejection.

   Every answer is an outcome of its own (bats-lang/quire#334), and
   anything this module does not recognise is AuthorizeUnexpected,
   ChangeUnexpected or PluginUnexpected, never a known outcome. JS only writes the answer
   down as text (CLAUDE.md, "An atom's JS only writes the answer
   down"); this module reads it with json and decides.

   Scopes cross as OAuth writes a list of them, separated by spaces
   (RFC 6749, 3.3): those asked for, and those granted. *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use promise as P
#use result as R
#use json as J

(* ============================================================
   Public API
   ============================================================ *)

(* How an authorization is asked for: Silently, never showing
   anything (authorizationForScopes), or MayAsk, showing Google's
   consent screen when the reader must consent first (authorizeScopes) *)
#pub datasort asking = Silently | MayAsk

(* A refusal Play services gives: a status CommonStatusCodes names
   (getStatusCodeString), but SUCCESS and SUCCESS_CACHE, which are no
   refusal *)
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

(* A token or an account, to hand Google or as Google gave it: a text
   of printable ASCII (0x21 to 0x7E), made by google_text_of, or by
   this module from an answer *)
#pub absvtype google_text = ptr

(* bytes[0, n) as a google_text, when they are printable ASCII *)
#pub fn google_text_of {l:agz}{n:pos | n <= 1048576} (bytes: !$A.borrow(byte, l, n), n: int n): $R.option(google_text)

(* A google_text's bytes, the text consumed *)
#pub fn google_text_bytes (text: google_text): [l:agz][n:pos] @($A.arr(byte, l, n), int n)

(* A google_text no call took *)
#pub fn google_text_free (text: google_text): void

(* The scopes Google granted: each a text of printable ASCII,
   separated by spaces (RFC 6749, 3.3), made only by this module from an
   answer, so no call takes it as a token or an account *)
#pub absvtype google_granted = ptr

(* A google_granted's bytes, consumed *)
#pub fn google_granted_bytes (granted: google_granted): [l:agz][n:pos] @($A.arr(byte, l, n), int n)

#pub fn google_granted_free (granted: google_granted): void

(* How JS wrote what came back: as JSON (JSON.stringify, an Error as
   its own properties and its name, a BigInt as its digits); as String
   gives it, when JSON.stringify threw or gave nothing; as its type,
   when String threw too; or as its type because the text it wrote
   could not be kept *)
#pub datatype google_form = AsJson | AsString | AsType | AsTypeTextUnkept

(* What came back, as JS wrote it and TextEncoder kept it as UTF-8 (a
   lone surrogate, which only the String form can hold, becomes
   U+FFFD), for a report (an access token in it too: one who prints it
   hides that): at most 1 MiB *)
#pub datavtype google_said = {n:nat | n <= 1048576} GoogleSaid of (google_form, dblob(n))

#pub fn google_said_free (said: google_said): void

(* What came back over 1 MiB as JS wrote it (array's alloc bound, and
   what this module reads): how JS wrote it, its whole length in
   bytes, and its first 1 MiB *)
#pub datavtype google_cut = {l:agz} GoogleCut of (google_form, int, $A.arr(byte, l, 1048576))

#pub fn google_cut_free (cut: google_cut): void

(* A text JS kept with an answer code it never gives, its form unknown:
   whole, at most 1 MiB; or its whole length in bytes and its first
   1 MiB *)
#pub datavtype google_raw =
  | {n:nat | n <= 1048576} RawWhole of dblob(n)
  | {l:agz} RawCut of (int, $A.arr(byte, l, 1048576))

#pub fn google_raw_free (raw: google_raw): void

(* Where the call was when what JS kept came: the plugin's answer
   resolved or was rejected; or looking the plugin up, reading the
   call's arguments, or calling its method threw *)
#pub datatype google_stage = StageResolved | StageRejected | StageLookup | StageArguments | StageMethod

(* What threw before the plugin answered: looking it up, reading the
   call's arguments, or calling its method *)
#pub datatype google_throw = LookupThrew | ArgumentsThrew | MethodThrew

(* What kind of JSON value a part was *)
#pub datatype json_kind = KindNull | KindBool | KindNumber | KindString | KindArray | KindObject

(* Why an answer has no authorization object: no authorization key;
   a null one from authorizeScopes, which documents it always gives
   one; or one that is neither null nor an object *)
#pub datatype authorization_flaw = AuthorizationMissing | AuthorizationNull | AuthorizationNotObject

(* Why a text part (the token, or the account) cannot be used: it is
   missing; it is not a string (for the account, neither null nor a
   string); it is empty; or it holds a byte that is not printable
   ASCII (0x21 to 0x7E) *)
#pub datatype text_flaw = TextMissing | TextNotString | TextEmpty | TextNotPrintable

(* Why the granted scopes cannot be used: missing; not a list; an
   empty list; a scope that is not a string, that is empty, or that
   holds a byte that is not printable ASCII; or the scopes, joined by
   spaces, over 1 MiB (array's alloc bound: an answer of at most 1 MiB
   holds no such list, so this module never gives it, but its types
   do not show that) *)
#pub datatype scopes_flaw =
  | ScopesMissing | ScopesNotList | ScopesEmpty
  | ScopeNotString | ScopeEmpty | ScopeNotPrintable | ScopesTooLong

(* Why a rejection's code names no outcome of the call: the plugin's
   UNEXPECTED; INVALID_OPTIONS, which this module's types rule out;
   SUCCESS; SUCCESS_CACHE; CONSENT_SHOWING from a call that shows no
   consent screen; a non-empty code nothing documents; the empty code;
   a null code; or no code *)
#pub datatype rejection_code =
  | CodeUnexpected | CodeInvalidOptions | CodeSuccess | CodeSuccessCache
  | CodeConsentShowing | CodeUnknown | CodeEmpty | CodeNull | CodeMissing

(* What an answer this module does not recognise was, each case once,
   with what JS kept of it *)
#pub datavtype google_unexpected =
  (* authorizationForScopes or authorizeScopes resolved with undefined *)
  | AnswerUndefined
  (* An answer that is not JSON (written as String gives it, or as its
     type) *)
  | AnswerNotJson of google_said
  (* An answer that is JSON json's parse refuses, and json's error *)
  | AnswerUnparsed of (google_said, $J.parse_error)
  (* An answer over 1 MiB as JS wrote it, cut there *)
  | AnswerTooLarge of google_cut
  (* An answer that is JSON but no object (its kind) *)
  | AnswerNotObject of (json_kind, google_said)
  (* An object with no authorization object, and why *)
  | NoAuthorization of (authorization_flaw, google_said)
  (* An authorization whose accessToken cannot be used, and why *)
  | TokenUnusable of (text_flaw, google_said)
  (* An authorization whose grantedScopes cannot be used, and why *)
  | ScopesUnusable of (scopes_flaw, google_said)
  (* An authorization whose account is neither null nor usable, and
     why *)
  | AccountUnusable of (text_flaw, google_said)
  (* clearAuthorizationToken or revokeAccess resolved with a value,
     where it documents none *)
  | ChangeResolvedWith of google_said
  (* A rejection with undefined *)
  | RejectionUndefined
  (* A rejection that is not JSON *)
  | RejectionNotJson of google_said
  (* A rejection that is JSON json's parse refuses, and json's error *)
  | RejectionUnparsed of (google_said, $J.parse_error)
  (* A rejection over 1 MiB as JS wrote it, cut there *)
  | RejectionTooLarge of google_cut
  (* A rejection that is JSON but no object (its kind) *)
  | RejectionNotObject of (json_kind, google_said)
  (* A rejection whose code is neither a string, null nor missing (its
     kind) *)
  | CodeNotText of (json_kind, google_said)
  (* A rejection whose code names no outcome of the call, and which
     code it was *)
  | RejectedOther of (rejection_code, google_said)
  (* Something threw before the plugin answered: what, and what it
     threw *)
  | Thrown of (google_throw, google_said)
  (* Something threw undefined before the plugin answered *)
  | ThrownUndefined of google_throw
  (* Something threw before the plugin answered, a text over 1 MiB as
     JS wrote it, cut there *)
  | ThrownTooLarge of (google_throw, google_cut)
  (* JS could keep no text of what came, nor its type: where the call
     was *)
  | NothingKept of google_stage
  (* An answer code JS never gives, and the text it kept, if any *)
  | OddAnswer of (int, $R.option(google_raw))

#pub fn google_unexpected_free (unexpected: google_unexpected): void

(* What asking for an authorization came to, decoded here, once, from
   the answer as JS wrote it. Linear: an answer no consumer takes is
   freed by promise's dispose. *)
#pub datavtype google_authorization(asking) =
  (* The access token; the scopes granted, separated by spaces; the
     account the grant is for, when the answer names one; and the
     answer as JS wrote it (the token in it too), with any field this
     module does not read *)
  | {w:asking} Authorized(w) of (google_text, google_granted, $R.option(google_text), google_said)
  (* The reader must consent first, and nothing was shown; the answer
     as JS wrote it *)
  | NotAuthorized(Silently) of google_said
  (* authorizeScopes answered CANCELED: the reader backed out of the
     consent screen (the plugin gives the same code for a CANCELED
     status before any consent screen, bats-lang/capacitor-plugins#8),
     and the rejection *)
  | AuthorizeCanceled(MayAsk) of google_said
  (* Another call's consent screen was showing (CONSENT_SHOWING), and
     the rejection *)
  | ConsentShowing(MayAsk) of google_said
  (* Play services refused, with its status, and the rejection
     (CANCELED from authorizationForScopes among them) *)
  | {w:asking} AuthorizeRefused(w) of (google_status, google_said)
  (* No plugin: none when there is no plugin to call (a browser), else
     the platform's UNIMPLEMENTED rejection *)
  | {w:asking} AuthorizeUnavailable(w) of $R.option(google_said)
  (* An answer this module does not recognise, and what it was *)
  | {w:asking} AuthorizeUnexpected(w) of google_unexpected

(* How clearing a token or revoking a grant ended *)
#pub datavtype google_authorization_change =
  (* Cleared, or taken back: the call resolved with undefined, as the
     plugin documents *)
  | Changed
  (* Play services refused, with its status, and the rejection *)
  | ChangeRefused of (google_status, google_said)
  (* No plugin: none when there is no plugin to call, else the
     platform's UNIMPLEMENTED rejection *)
  | ChangeUnavailable of $R.option(google_said)
  (* An answer this module does not recognise, and what it was *)
  | ChangeUnexpected of google_unexpected

(* Whether the app has the plugin: present, absent (a browser), or
   looking it up gave what this module does not recognise *)
#pub datavtype google_presence =
  | PluginPresent
  | PluginAbsent
  | PluginUnexpected of google_unexpected

#pub fun google_authorize_available(): google_presence

(* An OAuth scope of n bytes: a text of printable ASCII (0x21 to 0x7E,
   so no whitespace), made only by google_scope_of *)
#pub abstype google_scope(int) = ptr

(* text as a scope, when it is printable ASCII *)
#pub fn google_scope_of {n:pos} (text: string n): $R.option(google_scope(n))

(* A scope's text *)
#pub fn google_scope_text {n:pos} (scope: google_scope(n)): string n

(* The scopes of a call, at least one, t bytes as they cross (each
   scope's text, separated by spaces) *)
#pub datavtype google_scopes(int) =
  | {n:pos} OneScope(n) of google_scope(n)
  | {n,t:pos} MoreScopes(n + 1 + t) of (google_scope(n), google_scopes(t))

(* The access token for scopes when they are already granted, showing
   nothing: authorizationForScopes *)
#pub fun google_authorization_for_scopes
  {t:pos | t <= 1048576}
  (scopes: google_scopes(t))
  : $P.promise(google_authorization(Silently), $P.Chained)

(* The access token for scopes, showing Google's consent screen when
   the reader must consent first: authorizeScopes *)
#pub fun google_authorize_scopes
  {t:pos | t <= 1048576}
  (scopes: google_scopes(t))
  : $P.promise(google_authorization(MayAsk), $P.Chained)

(* Takes the access token out of Play services' cache:
   clearAuthorizationToken *)
#pub fun google_clear_token (token: google_text)
  : $P.promise(google_authorization_change, $P.Chained)

(* Takes back the account's grant of scopes (an Authorized answer's
   account): revokeAccess *)
#pub fun google_revoke_access
  {t:pos | t <= 1048576}
  (account: google_text, scopes: google_scopes(t))
  : $P.promise(google_authorization_change, $P.Chained)

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

$UNSAFE begin
%{
extern int bats_js_google_authorize_available(void);
extern void bats_js_google_authorize(void*, int, int, int);
extern int bats_js_google_authorize_text(int);
extern void bats_js_google_clear_token(void*, int, int);
extern void bats_js_google_revoke_access(void*, int, void*, int, int);
%}
extern fun _bats_js_google_authorize_available
  (): int = "mac#bats_js_google_authorize_available"
extern fun _bats_js_google_authorize
  (scopes: ptr, scopes_len: int, may_ask: int, resolver_id: int)
  : void = "mac#bats_js_google_authorize"
extern fun _bats_js_google_authorize_text
  (resolver_id: int): int = "mac#bats_js_google_authorize_text"
extern fun _bats_js_google_clear_token
  (token: ptr, token_len: int, resolver_id: int)
  : void = "mac#bats_js_google_clear_token"
extern fun _bats_js_google_revoke_access
  (account: ptr, account_len: int, scopes: ptr, scopes_len: int, resolver_id: int)
  : void = "mac#bats_js_google_revoke_access"
end

(* The text JS kept for the request, as JS wrote the answer: taken
   once, none when JS kept none *)
fn _text (resolver_id: int): $R.option([n:nat] dblob(n)) = let
  val handle = _bats_js_google_authorize_text(resolver_id)
in
  if handle <= 0 then $R.none()
  else blob_claim($UNSAFE begin $UNSAFE.cast{blob_handle}(handle) end)
end

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

implement google_said_free (said) = let
  val ~GoogleSaid(_, text) = said
in blob_free(text) end

implement google_cut_free (cut) = let
  val ~GoogleCut(_, _, bytes) = cut
in $A.free<byte>(bytes) end

fn _free_said (said: $R.option(google_said)): void =
  case+ said of ~$R.some(kept) => google_said_free(kept) | ~$R.none() => ()

fn _free_error (error: $J.parse_error): void = let val _ = $J.parse_error_pos(error) in end

implement google_raw_free (raw) =
  case+ raw of
  | ~RawWhole(blob) => blob_free(blob)
  | ~RawCut(_, bytes) => $A.free<byte>(bytes)

implement google_unexpected_free (unexpected) =
  case+ unexpected of
  | ~AnswerUndefined() => ()
  | ~AnswerNotJson(said) => google_said_free(said)
  | ~AnswerUnparsed(said, error) => let val () = _free_error(error) in google_said_free(said) end
  | ~AnswerTooLarge(cut) => google_cut_free(cut)
  | ~AnswerNotObject(_, said) => google_said_free(said)
  | ~NoAuthorization(_, said) => google_said_free(said)
  | ~TokenUnusable(_, said) => google_said_free(said)
  | ~ScopesUnusable(_, said) => google_said_free(said)
  | ~AccountUnusable(_, said) => google_said_free(said)
  | ~ChangeResolvedWith(said) => google_said_free(said)
  | ~RejectionUndefined() => ()
  | ~RejectionNotJson(said) => google_said_free(said)
  | ~RejectionUnparsed(said, error) => let val () = _free_error(error) in google_said_free(said) end
  | ~RejectionTooLarge(cut) => google_cut_free(cut)
  | ~RejectionNotObject(_, said) => google_said_free(said)
  | ~CodeNotText(_, said) => google_said_free(said)
  | ~RejectedOther(_, said) => google_said_free(said)
  | ~Thrown(_, said) => google_said_free(said)
  | ~ThrownUndefined(_) => ()
  | ~ThrownTooLarge(_, cut) => google_cut_free(cut)
  | ~NothingKept(_) => ()
  | ~OddAnswer(_, text) => (case+ text of ~$R.some(raw) => google_raw_free(raw) | ~$R.none() => ())

(* ------------------------------------------------------------
   Reading what JS wrote
   ------------------------------------------------------------ *)

(* What JS kept: the text, at most 1 MiB, or its first 1 MiB and its
   whole length *)
datavtype kept =
  | Whole of google_said
  | Over of google_cut

(* How much of n bytes the first 1 MiB holds *)
fn _first {n:nat} (n: int n): [count:nat | count <= n; count <= 1048576] int count =
  if n >= 1048576 then 1048576 else n

fn _kept {n:nat} (form: google_form, text: dblob(n)): kept = let
  val n = blob_len(text)
in
  if n <= 1048576 then Whole(GoogleSaid(form, text))
  else let
    val bytes = $A.alloc<byte>(1048576)
    val () = blob_read(text, 0, bytes, _first(n))
    val () = blob_free(text)
  in Over(GoogleCut(form, n, bytes)) end
end

(* An odd answer's text, capped as _kept caps one *)
fn _raw (text: $R.option([n:nat] dblob(n))): $R.option(google_raw) =
  case+ text of
  | ~$R.none() => $R.none()
  | ~$R.some(blob) => let
      val n = blob_len(blob)
    in
      if n <= 1048576 then $R.some(RawWhole(blob))
      else let
        val bytes = $A.alloc<byte>(1048576)
        val () = blob_read(blob, 0, bytes, _first(n))
        val () = blob_free(blob)
      in $R.some(RawCut(n, bytes)) end
    end

(* What a JSON text holds: a value json's parse_text reads, or json's
   error (an empty text ends before any value, at 0) *)
datavtype reading =
  | Read of $J.json_v
  | Refused of $J.parse_error

fn _read (said: !google_said): reading = let
  val @GoogleSaid(_, text) = said
  val n = blob_len(text)
  val value = (
    if n <= 0 then Refused($J.UnexpectedEnd(0))
    else let
      val bytes = $A.alloc<byte>(n)
      val () = blob_read(text, 0, bytes, n)
      val @(frozen, borrowed) = $A.freeze<byte>(bytes)
      val parsed = $J.parse_text(borrowed, n)
      val () = $A.drop<byte>(frozen, borrowed)
      val () = $A.free<byte>($A.thaw<byte>(frozen))
    in
      case+ parsed of
      | ~$R.ok(v) => Read(v)
      | ~$R.err(error) => Refused(error)
    end): reading
  prval () = fold@(said)
in value end

(* A JSON value's kind, the value freed *)
fn _kind (value: $J.json_v): json_kind =
  case+ value of
  | ~$J.json_null() => KindNull()
  | ~$J.json_bool(_) => KindBool()
  | ~$J.json_num(bytes, _, number) => let
      val () = $A.free<byte>(bytes)
      val () = (case+ number of ~$R.some(_) => () | ~$R.none() => ())
    in KindNumber() end
  | ~$J.json_str(bytes, _) => let val () = $A.free<byte>(bytes) in KindString() end
  | ~$J.json_arr(list) => let val () = $J.json_list_free(list) in KindArray() end
  | ~$J.json_obj(entries) => let val () = $J.json_entries_free(entries) in KindObject() end

(* Whether bytes[at, length) are text's, from at on *)
fun _same {l:agz}{size:nat}{length:nat | length <= size}{n:nat}{at:nat | at <= n} .<n - at>.
  (bytes: !$A.arr(byte, l, size), length: int length, text: string n, n: int n, at: int at): bool =
  if at >= n then true
  else if at >= length then false
  else if byte2int0($A.get<byte>(bytes, at)) <> char2int0(string_get_at(text, at)) then false
  else _same(bytes, length, text, n, at + 1)

(* Whether bytes[0, length) are exactly text *)
fn _is {l:agz}{size:nat}{length:nat | length <= size}{n:nat}
  (bytes: !$A.arr(byte, l, size), length: int length, text: string n): bool = let
  val n = g1u2i(string1_length(text))
in if length <> n then false else _same(bytes, length, text, n, 0) end

(* The status bytes[0, length) names: status and at most fuel after it,
   or none *)
fun _status_from {l:agz}{size:nat}{length:nat | length <= size}{fuel:nat} .<fuel>.
  (bytes: !$A.arr(byte, l, size), length: int length, status: google_status, fuel: int fuel): $R.option(google_status) =
  if _is(bytes, length, google_status_name(status)) then $R.some(status)
  else if fuel <= 0 then $R.none()
  else case+ _status_after(status) of
    | ~$R.some(next) => _status_from(bytes, length, next, fuel - 1)
    | ~$R.none() => $R.none()

(* Whether bytes[at, length) are printable ASCII only (0x21 to 0x7E) *)
fun _printable_bytes {l:agz}{size:nat}{length:nat | length <= size}{at:nat | at <= length} .<length - at>.
  (bytes: !$A.arr(byte, l, size), length: int length, at: int at): bool =
  if at >= length then true
  else let
    val c = byte2int0($A.get<byte>(bytes, at))
  in if c >= 0x21 && c <= 0x7E then _printable_bytes(bytes, length, at + 1) else false end

(* to[at + j, at + count) := from[j, count) *)
fun _copy {l,c:agz}{size,total:nat}{count:nat | count <= size}{at:nat | at + count <= total}{j:nat | j <= count} .<count - j>.
  (from: !$A.arr(byte, l, size), count: int count, to: !$A.arr(byte, c, total), at: int at, j: int j): void =
  if j >= count then ()
  else let
    val () = $A.set<byte>(to, at + j, $A.get<byte>(from, j))
  in _copy(from, count, to, at, j + 1) end

datavtype text_rep = {l:agz}{n:pos} TextRep of ($A.arr(byte, l, n), int n)
$UNSAFE begin
assume google_text = text_rep
assume google_granted = text_rep
end

(* A JSON value as a google_text: a non-empty string of printable
   ASCII, or why not *)
fn _text_of (value: $J.json_v): $R.result(google_text, text_flaw) =
  case+ value of
  | ~$J.json_str(bytes, length) =>
    if length <= 0 then let val () = $A.free<byte>(bytes) in $R.err(TextEmpty()) end
    else if ~_printable_bytes(bytes, length, 0) then let val () = $A.free<byte>(bytes) in $R.err(TextNotPrintable()) end
    else let
      val copy = $A.alloc<byte>(length)
      val () = _copy(bytes, length, copy, 0, 0)
      val () = $A.free<byte>(bytes)
    in $R.ok(TextRep(copy, length)) end
  | other => let val _ = _kind(other) in $R.err(TextNotString()) end

(* The scopes, each followed by a space, at out[at], the list freed:
   how far they reach, or why they cannot be used *)
fun _scopes_put {sz:nat}{l:agz}{at:nat | at <= 1048576} .<sz>.
  (list: $J.json_list(sz), out: !$A.arr(byte, l, 1048576), at: int at)
  : $R.result([stop:nat | stop <= 1048576] int stop, scopes_flaw) =
  case+ list of
  | ~$J.json_list_nil() => $R.ok(at)
  | ~$J.json_list_cons(value, rest) => (case+ value of
    | ~$J.json_str(bytes, length) =>
      if length <= 0 then let
        val () = $A.free<byte>(bytes)
        val () = $J.json_list_free(rest)
      in $R.err(ScopeEmpty()) end
      else if ~_printable_bytes(bytes, length, 0) then let
        val () = $A.free<byte>(bytes)
        val () = $J.json_list_free(rest)
      in $R.err(ScopeNotPrintable()) end
      else if at + length + 1 > 1048576 then let
        val () = $A.free<byte>(bytes)
        val () = $J.json_list_free(rest)
      in $R.err(ScopesTooLong()) end
      else let
        val () = _copy(bytes, length, out, at, 0)
        val () = $A.free<byte>(bytes)
        val () = $A.set<byte>(out, at + length, int2byte0(32))
      in _scopes_put(rest, out, at + length + 1) end
    | other => let
        val _ = _kind(other)
        val () = $J.json_list_free(rest)
      in $R.err(ScopeNotString()) end)

(* A JSON value as the scopes granted: a non-empty list of strings of
   printable ASCII, written separated by spaces, or why not *)
fn _scopes_of (value: $J.json_v): $R.result(google_granted, scopes_flaw) =
  case+ value of
  | ~$J.json_arr(list) => let
      val out = $A.alloc<byte>(1048576)
      val stop = _scopes_put(list, out, 0)
    in
      case+ stop of
      | ~$R.ok(total) =>
        if total <= 1 then let val () = $A.free<byte>(out) in $R.err(ScopesEmpty()) end
        else let
          val copy = $A.alloc<byte>(total - 1)
          val () = _copy(out, total - 1, copy, 0, 0)
          val () = $A.free<byte>(out)
        in $R.ok(TextRep(copy, total - 1)) end
      | ~$R.err(flaw) => let val () = $A.free<byte>(out) in $R.err(flaw) end
    end
  | other => let val _ = _kind(other) in $R.err(ScopesNotList()) end

(* The value of key in an object's entries, the rest freed; the first,
   when a key comes twice *)
fun _take {sz:nat} .<sz>. (entries: $J.json_entries(sz), key: string): $R.option($J.json_v) =
  case+ entries of
  | ~$J.json_entries_nil() => $R.none()
  | ~$J.json_entries_cons(name, length, value, rest) =>
    if _is(name, length, g1ofg0(key)) then let
      val () = $A.free<byte>(name)
      val () = $J.json_entries_free(rest)
    in $R.some(value) end
    else let
      val () = $A.free<byte>(name)
      val () = $J.json_free(value)
    in _take(rest, key) end

fn _free_value (value: $R.option($J.json_v)): void =
  case+ value of ~$R.some(v) => $J.json_free(v) | ~$R.none() => ()

(* An authorization object's fields: accessToken, grantedScopes and
   account, each the first of its name, the rest freed *)
fun _fields {sz:nat} .<sz>. (entries: $J.json_entries(sz),
    token: $R.option($J.json_v), scopes: $R.option($J.json_v), account: $R.option($J.json_v))
  : @($R.option($J.json_v), $R.option($J.json_v), $R.option($J.json_v)) =
  case+ entries of
  | ~$J.json_entries_nil() => @(token, scopes, account)
  | ~$J.json_entries_cons(name, length, value, rest) =>
    if _is(name, length, "accessToken") && $R.is_none<$J.json_v>(token) then let
      val () = $A.free<byte>(name)
      val () = _free_value(token)
    in _fields(rest, $R.some(value), scopes, account) end
    else if _is(name, length, "grantedScopes") && $R.is_none<$J.json_v>(scopes) then let
      val () = $A.free<byte>(name)
      val () = _free_value(scopes)
    in _fields(rest, token, $R.some(value), account) end
    else if _is(name, length, "account") && $R.is_none<$J.json_v>(account) then let
      val () = $A.free<byte>(name)
      val () = _free_value(account)
    in _fields(rest, token, scopes, $R.some(value)) end
    else let
      val () = $A.free<byte>(name)
      val () = $J.json_free(value)
    in _fields(rest, token, scopes, account) end

(* ------------------------------------------------------------
   Decoding
   ------------------------------------------------------------ *)

(* A rejection, decoded: one of Play services' statuses (CANCELED
   among them, which is also the plugin's own code for a cancel: _asked
   tells the calls apart), the plugin's CONSENT_SHOWING, Capacitor's
   UNIMPLEMENTED, or what this module does not recognise *)
datavtype failure =
  | FailedStatus of (google_status, google_said)
  | FailedConsentShowing of google_said
  | FailedUnavailable of $R.option(google_said)
  | FailedOther of google_unexpected

(* The code of a rejection that names no status *)
fn _odd_code {l:agz}{size:nat}{length:nat | length <= size}
  (bytes: !$A.arr(byte, l, size), length: int length): rejection_code =
  if length <= 0 then CodeEmpty()
  else if _is(bytes, length, "UNEXPECTED") then CodeUnexpected()
  else if _is(bytes, length, "INVALID_OPTIONS") then CodeInvalidOptions()
  else if _is(bytes, length, "SUCCESS") then CodeSuccess()
  else if _is(bytes, length, "SUCCESS_CACHE") then CodeSuccessCache()
  else CodeUnknown()

(* A rejection JS wrote as JSON *)
fn _rejection (said: google_said): failure =
  case+ _read(said) of
  | ~Refused(error) => FailedOther(RejectionUnparsed(said, error))
  | ~Read(value) => (case+ value of
    | ~$J.json_obj(entries) => (case+ _take(entries, "code") of
      | ~$R.none() => FailedOther(RejectedOther(CodeMissing(), said))
      | ~$R.some(code) => (case+ code of
        | ~$J.json_null() => FailedOther(RejectedOther(CodeNull(), said))
        | ~$J.json_str(bytes, length) =>
          if _is(bytes, length, "CONSENT_SHOWING") then let
            val () = $A.free<byte>(bytes)
          in FailedConsentShowing(said) end
          else if _is(bytes, length, "UNIMPLEMENTED") then let
            val () = $A.free<byte>(bytes)
          in FailedUnavailable($R.some(said)) end
          else let
            val status = _status_from(bytes, length, StatusServiceVersionUpdateRequired(), 18)
          in
            case+ status of
            | ~$R.some(named) => let val () = $A.free<byte>(bytes) in FailedStatus(named, said) end
            | ~$R.none() => let
                val odd = _odd_code(bytes, length)
                val () = $A.free<byte>(bytes)
              in FailedOther(RejectedOther(odd, said)) end
          end
        | other => FailedOther(CodeNotText(_kind(other), said))))
    | other => FailedOther(RejectionNotObject(_kind(other), said)))

(* An authorization JS wrote as JSON, decoded: a token, none (the
   authorization is null), or a failure *)
datavtype answer =
  | AnswerToken of (google_text, google_granted, $R.option(google_text), google_said)
  | AnswerNone of google_said
  | AnswerFailed of failure

(* An authorization object's fields, decoded: the token, the scopes,
   then the account *)
fn _authorized (said: google_said, token: $R.option($J.json_v), scopes: $R.option($J.json_v), account: $R.option($J.json_v)): answer = let
  val token = (case+ token of ~$R.some(v) => _text_of(v) | ~$R.none() => $R.err(TextMissing())): $R.result(google_text, text_flaw)
in
  case+ token of
  | ~$R.err(flaw) => let
      val () = _free_value(scopes)
      val () = _free_value(account)
    in AnswerFailed(FailedOther(TokenUnusable(flaw, said))) end
  | ~$R.ok(token) => let
      val scopes = (case+ scopes of ~$R.some(v) => _scopes_of(v) | ~$R.none() => $R.err(ScopesMissing())): $R.result(google_granted, scopes_flaw)
    in
      case+ scopes of
      | ~$R.err(flaw) => let
          val () = google_text_free(token)
          val () = _free_value(account)
        in AnswerFailed(FailedOther(ScopesUnusable(flaw, said))) end
      | ~$R.ok(scopes) => (case+ account of
        | ~$R.none() => let
            val () = google_text_free(token)
            val () = google_granted_free(scopes)
          in AnswerFailed(FailedOther(AccountUnusable(TextMissing(), said))) end
        | ~$R.some(value) => (case+ value of
          | ~$J.json_null() => AnswerToken(token, scopes, $R.none(), said)
          | other => (case+ _text_of(other) of
            | ~$R.ok(named) => AnswerToken(token, scopes, $R.some(named), said)
            | ~$R.err(flaw) => let
                val () = google_text_free(token)
                val () = google_granted_free(scopes)
              in AnswerFailed(FailedOther(AccountUnusable(flaw, said))) end)))
    end
end

(* An authorization JS wrote as JSON *)
fn _resolved (said: google_said): answer =
  case+ _read(said) of
  | ~Refused(error) => AnswerFailed(FailedOther(AnswerUnparsed(said, error)))
  | ~Read(value) => (case+ value of
    | ~$J.json_obj(entries) => (case+ _take(entries, "authorization") of
      | ~$R.none() => AnswerFailed(FailedOther(NoAuthorization(AuthorizationMissing(), said)))
      | ~$R.some(authorization) => (case+ authorization of
        | ~$J.json_null() => AnswerNone(said)
        | ~$J.json_obj(fields) => let
            val @(token, scopes, account) = _fields(fields, $R.none(), $R.none(), $R.none())
          in _authorized(said, token, scopes, account) end
        | other => let val _ = _kind(other) in AnswerFailed(FailedOther(NoAuthorization(AuthorizationNotObject(), said))) end))
    | other => AnswerFailed(FailedOther(AnswerNotObject(_kind(other), said))))

(* The form JS's answer code names (its last digit): 1 JSON, 2 String,
   3 its type, 5 its type for a text not kept; none for 4 (undefined)
   and 6 (nothing kept), which keep no text, and any other *)
fn _form (digit: int): $R.option(google_form) =
  if digit = 1 then $R.some(AsJson())
  else if digit = 2 then $R.some(AsString())
  else if digit = 3 then $R.some(AsType())
  else if digit = 5 then $R.some(AsTypeTextUnkept())
  else $R.none()

(* The stage JS's answer code names (its tens): 1 resolved, 2
   rejected, 3 the lookup threw, 4 reading the arguments threw, 5 the
   method threw *)
fn _stage (tens: int): $R.option(google_stage) =
  if tens = 1 then $R.some(StageResolved())
  else if tens = 2 then $R.some(StageRejected())
  else if tens = 3 then $R.some(StageLookup())
  else if tens = 4 then $R.some(StageArguments())
  else if tens = 5 then $R.some(StageMethod())
  else $R.none()

(* What came back: a text kept, undefined, or nothing kept *)
datavtype came =
  | CameText of kept
  | CameUndefined
  | CameNothing

(* What JS answered, before it is one of an atom's *)
datavtype answered =
  | NoPlugin
  | Answered of (google_stage, came)
  | Odd of (int, $R.option([n:nat] dblob(n)))

fn _answered (number: int, text: $R.option([n:nat] dblob(n))): answered =
  if number = 0 then (case+ text of
    | ~$R.none() => NoPlugin()
    | ~$R.some(blob) => Odd(number, $R.some(blob)))
  else if number < 10 || number > 56 then Odd(number, text)
  else let
    val tens = number / 10
    val digit = number - tens * 10
  in
    case+ _stage(tens) of
    | ~$R.none() => Odd(number, text)
    | ~$R.some(stage) => (case+ _form(digit) of
      | ~$R.some(form) => (case+ text of
        | ~$R.some(blob) => Answered(stage, CameText(_kept(form, blob)))
        | ~$R.none() => Odd(number, $R.none()))
      | ~$R.none() =>
        if digit = 4 then (case+ text of
          | ~$R.none() => Answered(stage, CameUndefined())
          | ~$R.some(blob) => Odd(number, $R.some(blob)))
        else if digit = 6 then (case+ text of
          | ~$R.none() => Answered(stage, CameNothing())
          | ~$R.some(blob) => Odd(number, $R.some(blob)))
        else Odd(number, text))
  end

(* The stage at which what threw *)
fn _stage_of (what: google_throw): google_stage =
  case+ what of
  | LookupThrew() => StageLookup()
  | ArgumentsThrew() => StageArguments()
  | MethodThrew() => StageMethod()

(* What threw, as an unexpected answer *)
fn _thrown (what: google_throw, came: came): google_unexpected =
  case+ came of
  | ~CameText(~Whole(said)) => Thrown(what, said)
  | ~CameText(~Over(cut)) => ThrownTooLarge(what, cut)
  | ~CameUndefined() => ThrownUndefined(what)
  | ~CameNothing() => NothingKept(_stage_of(what))

(* A rejection's text *)
fn _rejected (came: came): failure =
  case+ came of
  | ~CameText(~Whole(said)) => (case+ said of
    | GoogleSaid(AsJson(), _) => _rejection(said)
    | _ => FailedOther(RejectionNotJson(said)))
  | ~CameText(~Over(cut)) => FailedOther(RejectionTooLarge(cut))
  | ~CameUndefined() => FailedOther(RejectionUndefined())
  | ~CameNothing() => FailedOther(NothingKept(StageRejected()))

(* An authorization's answer *)
fn _answer (answered: answered): answer =
  case+ answered of
  | ~NoPlugin() => AnswerFailed(FailedUnavailable($R.none()))
  | ~Odd(number, text) => AnswerFailed(FailedOther(OddAnswer(number, _raw(text))))
  | ~Answered(stage, came) => (case+ stage of
    | StageResolved() => (case+ came of
      | ~CameText(~Whole(said)) => (case+ said of
        | GoogleSaid(AsJson(), _) => _resolved(said)
        | _ => AnswerFailed(FailedOther(AnswerNotJson(said))))
      | ~CameText(~Over(cut)) => AnswerFailed(FailedOther(AnswerTooLarge(cut)))
      | ~CameUndefined() => AnswerFailed(FailedOther(AnswerUndefined()))
      | ~CameNothing() => AnswerFailed(FailedOther(NothingKept(StageResolved()))))
    | StageRejected() => AnswerFailed(_rejected(came))
    | StageLookup() => AnswerFailed(FailedOther(_thrown(LookupThrew(), came)))
    | StageArguments() => AnswerFailed(FailedOther(_thrown(ArgumentsThrew(), came)))
    | StageMethod() => AnswerFailed(FailedOther(_thrown(MethodThrew(), came))))

(* A failure of authorizationForScopes: it shows no consent screen, so
   CONSENT_SHOWING is a code it does not document *)
fn _found_failure (failure: failure): google_authorization(Silently) =
  case+ failure of
  | ~FailedStatus(status, said) => AuthorizeRefused(status, said)
  | ~FailedConsentShowing(said) => AuthorizeUnexpected(RejectedOther(CodeConsentShowing(), said))
  | ~FailedUnavailable(said) => AuthorizeUnavailable(said)
  | ~FailedOther(unexpected) => AuthorizeUnexpected(unexpected)

(* authorizationForScopes' answer: Play services' CANCELED from it
   (it shows nothing to cancel) is a refusal like any other status *)
fn _found (answer: answer): google_authorization(Silently) =
  case+ answer of
  | ~AnswerToken(token, scopes, account, said) => Authorized(token, scopes, account, said)
  | ~AnswerNone(said) => NotAuthorized(said)
  | ~AnswerFailed(failure) => _found_failure(failure)

(* authorizeScopes' answer: it always gives an authorization when it
   resolves, so a null one is unexpected; CANCELED, decoded here alone,
   is AuthorizeCanceled: the plugin's code for the reader backing out,
   which a CANCELED status Play services gives before any consent
   screen shares (bats-lang/capacitor-plugins#8) *)
fn _asked (answer: answer): google_authorization(MayAsk) =
  case+ answer of
  | ~AnswerToken(token, scopes, account, said) => Authorized(token, scopes, account, said)
  | ~AnswerNone(said) => AuthorizeUnexpected(NoAuthorization(AuthorizationNull(), said))
  | ~AnswerFailed(failure) => (case+ failure of
    | ~FailedStatus(status, said) => (case+ status of
      | StatusCanceled() => AuthorizeCanceled(said)
      | _ =>> AuthorizeRefused(status, said))
    | ~FailedConsentShowing(said) => ConsentShowing(said)
    | ~FailedUnavailable(said) => AuthorizeUnavailable(said)
    | ~FailedOther(unexpected) => AuthorizeUnexpected(unexpected))

(* clearAuthorizationToken's and revokeAccess': resolved with undefined
   is done, as the plugin documents; neither shows a consent screen *)
fn _change (answered: answered): google_authorization_change = let
  fn failed (failure: failure): google_authorization_change =
    case+ failure of
    | ~FailedStatus(status, said) => ChangeRefused(status, said)
    | ~FailedConsentShowing(said) => ChangeUnexpected(RejectedOther(CodeConsentShowing(), said))
    | ~FailedUnavailable(said) => ChangeUnavailable(said)
    | ~FailedOther(unexpected) => ChangeUnexpected(unexpected)
in
  case+ answered of
  | ~NoPlugin() => ChangeUnavailable($R.none())
  | ~Odd(number, text) => ChangeUnexpected(OddAnswer(number, _raw(text)))
  | ~Answered(stage, came) => (case+ stage of
    | StageResolved() => (case+ came of
      | ~CameUndefined() => Changed()
      | ~CameText(~Whole(said)) => ChangeUnexpected(ChangeResolvedWith(said))
      | ~CameText(~Over(cut)) => ChangeUnexpected(AnswerTooLarge(cut))
      | ~CameNothing() => ChangeUnexpected(NothingKept(StageResolved())))
    | StageRejected() => failed(_rejected(came))
    | StageLookup() => ChangeUnexpected(_thrown(LookupThrew(), came))
    | StageArguments() => ChangeUnexpected(_thrown(ArgumentsThrew(), came))
    | StageMethod() => ChangeUnexpected(_thrown(MethodThrew(), came)))
end

fn {} _free_authorization {w:asking} (answer: google_authorization(w)): void =
  case+ answer of
  | ~Authorized(token, scopes, account, said) => let
      val () = google_text_free(token)
      val () = google_granted_free(scopes)
      val () = google_said_free(said)
    in case+ account of ~$R.some(named) => google_text_free(named) | ~$R.none() => () end
  | ~NotAuthorized(said) => google_said_free(said)
  | ~AuthorizeCanceled(said) => google_said_free(said)
  | ~ConsentShowing(said) => google_said_free(said)
  | ~AuthorizeRefused(_, said) => google_said_free(said)
  | ~AuthorizeUnavailable(said) => _free_said(said)
  | ~AuthorizeUnexpected(unexpected) => google_unexpected_free(unexpected)

(* Answers nobody took: their blobs are freed. Before their first use *)
implement $P.dispose<google_authorization(Silently)>(answer) = _free_authorization(answer)
implement $P.dispose<google_authorization(MayAsk)>(answer) = _free_authorization(answer)
implement $P.dispose<google_authorization_change>(change) =
  case+ change of
  | ~Changed() => ()
  | ~ChangeRefused(_, said) => google_said_free(said)
  | ~ChangeUnavailable(said) => _free_said(said)
  | ~ChangeUnexpected(unexpected) => google_unexpected_free(unexpected)

(* The availability check: 1 present, 0 absent, else the lookup's
   answer code, its text kept under -1 *)
implement google_authorize_available() = let
  val number = _bats_js_google_authorize_available()
in
  if number = 1 then PluginPresent()
  else if number = 0 then PluginAbsent()
  else let
    val text = _text(~1)
  in
    (* only the lookup is done there, so only its codes (3x) come *)
    if number / 10 <> 3 then PluginUnexpected(OddAnswer(number, _raw(text)))
    else PluginUnexpected((case+ _answered(number, text) of
      | ~Answered(_, came) => _thrown(LookupThrew(), came)
      | ~NoPlugin() => OddAnswer(number, $R.none())
      | ~Odd(odd, kept) => OddAnswer(odd, _raw(kept))): google_unexpected)
  end
end

$UNSAFE begin
assume google_scope(n:int) = string n
end

(* Whether text[at, n) is printable ASCII only (0x21 to 0x7E) *)
fun _printable_text {n:pos}{at:nat | at <= n} .<n - at>. (text: string n, n: int n, at: int at): bool =
  if at >= n then true
  else let
    val c = char2int0(string_get_at(text, at))
  in if c >= 0x21 && c <= 0x7E then _printable_text(text, n, at + 1) else false end

implement google_scope_of (text) = let
  val n = g1u2i(string1_length(text))
in if _printable_text(text, n, 0) then $R.some(text) else $R.none() end

implement google_scope_text (scope) = scope

(* How many bytes scopes take as they cross *)
fun _scopes_bytes {t:pos} .<t>. (scopes: !google_scopes(t)): int t =
  case+ scopes of
  | @OneScope(scope) => let
      val n = g1u2i(string1_length(google_scope_text(scope)))
      prval () = fold@(scopes)
    in n end
  | @MoreScopes(scope, rest) => let
      val n = g1u2i(string1_length(google_scope_text(scope)))
      val after = _scopes_bytes(rest)
      prval () = fold@(scopes)
    in n + 1 + after end

(* scopes' texts, separated by spaces (RFC 6749, 3.3), at out[at]. The
   scopes are consumed *)
fun _scopes_put {l:agz}{size:pos}{t:pos}{at:nat | at + t <= size} .<t>.
  (scopes: google_scopes(t), out: !$A.arr(byte, l, size), at: int at): void =
  case+ scopes of
  | ~OneScope(scope) => let
      val text = google_scope_text(scope)
      val n = g1u2i(string1_length(text))
    in $A.write_text(out, at, $A.text_lit(text), n) end
  | ~MoreScopes(scope, rest) => let
      val text = google_scope_text(scope)
      val n = g1u2i(string1_length(text))
      val () = $A.write_text(out, at, $A.text_lit(text), n)
      val () = $A.write_byte(out, at + n, 32)
    in _scopes_put(rest, out, at + n + 1) end

(* Which call _ask makes: authorizationForScopes, or authorizeScopes *)
datatype asked_call = CallSilently | CallMayAsk

(* Asks JS for call; resolves with the resolver's id and JS's code *)
fn _ask {t:pos | t <= 1048576} (scopes: google_scopes(t), call: asked_call)
  : @(int, $P.promise(Int, $P.Pending)) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val stop = _scopes_bytes(scopes)
  val out = $A.alloc<byte>(stop)
  val () = _scopes_put(scopes, out, 0)
  val @(frozen, borrowed) = $A.freeze<byte>(out)
  val () = _bats_js_google_authorize(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(borrowed) end, stop,
    (case+ call of CallSilently() => 0 | CallMayAsk() => 1): int, id)
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in @(id, p) end

implement google_authorization_for_scopes{t}(scopes) = let
  val @(id, p) = _ask(scopes, CallSilently())
in $P.and_then<Int><google_authorization(Silently)>(p, llam (code) =>
  $P.ret<google_authorization(Silently)>(_found(_answer(_answered(code, _text(id)))))) end

implement google_authorize_scopes{t}(scopes) = let
  val @(id, p) = _ask(scopes, CallMayAsk())
in $P.and_then<Int><google_authorization(MayAsk)>(p, llam (code) =>
  $P.ret<google_authorization(MayAsk)>(_asked(_answer(_answered(code, _text(id)))))) end

(* Whether bytes[at, n) are printable ASCII only (0x21 to 0x7E) *)
fun _printable {l:agz}{n:pos}{at:nat | at <= n} .<n - at>. (bytes: !$A.borrow(byte, l, n), n: int n, at: int at): bool =
  if at >= n then true
  else let
    val c = byte2int0($A.read<byte>(bytes, at))
  in if c >= 0x21 && c <= 0x7E then _printable(bytes, n, at + 1) else false end

implement google_text_of {l}{n} (bytes, n) =
  if ~_printable(bytes, n, 0) then $R.none()
  else let
    val copy = $A.alloc<byte>(n)
    val () = $A.write_borrow(copy, 0, bytes, n)
  in $R.some(TextRep(copy, n)) end

implement google_text_bytes (text) =
  case+ text of ~TextRep(bytes, n) => @(bytes, n)

implement google_text_free (text) =
  case+ text of ~TextRep(bytes, _) => $A.free<byte>(bytes)

implement google_granted_bytes (granted) =
  case+ granted of ~TextRep(bytes, n) => @(bytes, n)

implement google_granted_free (granted) =
  case+ granted of ~TextRep(bytes, _) => $A.free<byte>(bytes)

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
  $P.ret<google_authorization_change>(_change(_answered(code, _text(id))))) end

implement google_revoke_access{t}(account, scopes) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val stop = _scopes_bytes(scopes)
  val out = $A.alloc<byte>(stop)
  val () = _scopes_put(scopes, out, 0)
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
  $P.ret<google_authorization_change>(_change(_answered(code, _text(id))))) end

end (* #target wasm *)
