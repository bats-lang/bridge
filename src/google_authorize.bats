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

   Every answer is an outcome of its own (bats-lang/quire#334), and
   anything this module does not recognise is AuthorizeUnexpected or
   ChangeUnexpected, never a known outcome. JS only writes the answer
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

(* A token, scopes or an account, to hand Google or as Google gave it:
   a text of printable ASCII (0x21 to 0x7E), made only by
   google_text_of or by this module from an answer *)
#pub absvtype google_text = ptr

(* bytes[0, n) as a google_text, when they are printable ASCII *)
#pub fn google_text_of {l:agz}{n:pos | n <= 1048576} (bytes: !$A.borrow(byte, l, n), n: int n): $R.option(google_text)

(* A google_text's bytes, the text consumed *)
#pub fn google_text_bytes (text: google_text): [l:agz][n:pos] @($A.arr(byte, l, n), int n)

(* A google_text no call took *)
#pub fn google_text_free (text: google_text): void

(* How JS wrote what the plugin answered: as JSON (JSON.stringify, an
   Error as its own properties and its name, a BigInt as its digits);
   as String gives it, when JSON.stringify threw or gave nothing; or as
   its type, when String threw too *)
#pub datatype google_form = AsJson | AsString | AsType

(* What the plugin answered, as JS wrote it, kept verbatim for a report
   (an access token in it too: one who prints it hides that) *)
#pub datavtype google_said = {n:nat} GoogleSaid of (google_form, dblob(n))

#pub fn google_said_free (said: google_said): void

(* An answer over 1 MiB as JS wrote it (array's alloc bound, and what
   this module reads): how JS wrote it, its whole length in bytes, and
   its first 1 MiB *)
#pub datavtype google_cut = {l:agz} GoogleCut of (google_form, int, $A.arr(byte, l, 1048576))

#pub fn google_cut_free (cut: google_cut): void

(* What an answer this module does not recognise was, each case once,
   with the answer as JS wrote it *)
#pub datavtype google_unexpected =
  (* An answer that is not JSON (AsString or AsType) *)
  | AnswerNotJson of google_said
  (* An answer that is JSON json's parse refuses, and json's error *)
  | AnswerUnparsed of (google_said, $J.parse_error)
  (* An answer over 1 MiB as JS wrote it, cut there *)
  | AnswerTooLarge of google_cut
  (* An answer that is not an object with an authorization object (null
     from authorizeScopes among them) *)
  | NoAuthorizationObject of google_said
  (* An authorization whose accessToken is not a string of printable
     ASCII *)
  | TokenNotPrintable of google_said
  (* An authorization whose grantedScopes is not a non-empty list of
     strings of printable ASCII *)
  | ScopesNotPrintable of google_said
  (* An authorization whose account is neither null nor a string of
     printable ASCII (a missing one among them) *)
  | AccountNotPrintable of google_said
  (* A rejection that is not JSON (AsString or AsType) *)
  | RejectionNotJson of google_said
  (* A rejection that is JSON json's parse refuses, and json's error *)
  | RejectionUnparsed of (google_said, $J.parse_error)
  (* A rejection over 1 MiB as JS wrote it, cut there *)
  | RejectionTooLarge of google_cut
  (* A rejection that is text *)
  | RejectionText of google_said
  (* A rejection that is neither an object nor text *)
  | RejectionNotObject of google_said
  (* A rejection whose code is neither text, null nor missing *)
  | CodeNotText of google_said
  (* A rejection whose code names no outcome of the call (the plugin's
     UNEXPECTED; INVALID_OPTIONS, which this module's types rule out;
     SUCCESS, SUCCESS_CACHE; CONSENT_SHOWING from a call that shows no
     consent screen; a code nothing documents, the empty one among
     them), or that has no code *)
  | RejectedOther of google_said
  (* Calling the plugin threw before it answered: what it threw *)
  | DecodeThrew of google_said
  (* An answer code JS never gives, and the text it kept, if any (its
     form unknown: the code is what would say it) *)
  | OddAnswer of (int, $R.option([n:nat] dblob(n)))

#pub fn google_unexpected_free (unexpected: google_unexpected): void

(* What asking for an authorization came to, decoded here, once, from
   the answer as JS wrote it. Linear: an answer no consumer takes is
   freed by promise's dispose. *)
#pub datavtype google_authorization(asking) =
  (* The access token; the scopes granted, separated by spaces; and
     the account the grant is for, when the answer names one *)
  | {w:asking} Authorized(w) of (google_text, google_text, $R.option(google_text))
  (* The reader must consent first, and nothing was shown *)
  | NotAuthorized(Silently)
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
  (* Cleared, or taken back: the call resolved *)
  | Changed
  (* Play services refused, with its status, and the rejection *)
  | ChangeRefused of (google_status, google_said)
  (* No plugin: none when there is no plugin to call, else the
     platform's UNIMPLEMENTED rejection *)
  | ChangeUnavailable of $R.option(google_said)
  (* An answer this module does not recognise, and what it was *)
  | ChangeUnexpected of google_unexpected

(* Whether the app has the plugin: false in a browser *)
#pub fun google_authorize_available(): bool

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

implement google_unexpected_free (unexpected) =
  case+ unexpected of
  | ~AnswerNotJson(said) => google_said_free(said)
  | ~AnswerUnparsed(said, error) => let val _ = $J.parse_error_pos(error) in google_said_free(said) end
  | ~AnswerTooLarge(cut) => google_cut_free(cut)
  | ~NoAuthorizationObject(said) => google_said_free(said)
  | ~TokenNotPrintable(said) => google_said_free(said)
  | ~ScopesNotPrintable(said) => google_said_free(said)
  | ~AccountNotPrintable(said) => google_said_free(said)
  | ~RejectionNotJson(said) => google_said_free(said)
  | ~RejectionUnparsed(said, error) => let val _ = $J.parse_error_pos(error) in google_said_free(said) end
  | ~RejectionTooLarge(cut) => google_cut_free(cut)
  | ~RejectionText(said) => google_said_free(said)
  | ~RejectionNotObject(said) => google_said_free(said)
  | ~CodeNotText(said) => google_said_free(said)
  | ~RejectedOther(said) => google_said_free(said)
  | ~DecodeThrew(said) => google_said_free(said)
  | ~OddAnswer(_, text) => (case+ text of ~$R.some(blob) => blob_free(blob) | ~$R.none() => ())

(* ------------------------------------------------------------
   Reading what JS wrote
   ------------------------------------------------------------ *)

(* What said's text holds: a JSON value json's parse_text reads, a
   text it refuses (and its error: an empty text ends before any value,
   at 0), or a text over 1 MiB *)
datavtype reading =
  | Read of $J.json_v
  | Refused of $J.parse_error
  | TooLarge

fn _read (said: !google_said): reading = let
  val @GoogleSaid(_, text) = said
  val n = blob_len(text)
  val value = (
    if n > 1048576 then TooLarge()
    else if n <= 0 then Refused($J.UnexpectedEnd(0))
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

(* How much of n bytes the first 1 MiB holds *)
fn _first {n:nat} (n: int n): [count:nat | count <= n; count <= 1048576] int count =
  if n >= 1048576 then 1048576 else n

(* said's first 1 MiB and its whole length, said freed *)
fn _cut (said: google_said): google_cut = let
  val ~GoogleSaid(form, text) = said
  val n = blob_len(text)
  val bytes = $A.alloc<byte>(1048576)
  val count = _first(n)
  val () = blob_read(text, 0, bytes, count)
  val () = blob_free(text)
in GoogleCut(form, n, bytes) end

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
end

(* A JSON value as a google_text: a string of printable ASCII *)
fn _text_of (value: $J.json_v): $R.option(google_text) =
  case+ value of
  | ~$J.json_str(bytes, length) =>
    if length <= 0 then let val () = $A.free<byte>(bytes) in $R.none() end
    else if ~_printable_bytes(bytes, length, 0) then let val () = $A.free<byte>(bytes) in $R.none() end
    else let
      val copy = $A.alloc<byte>(length)
      val () = _copy(bytes, length, copy, 0, 0)
      val () = $A.free<byte>(bytes)
    in $R.some(TextRep(copy, length)) end
  | other => let val () = $J.json_free(other) in $R.none() end

(* The scopes, each followed by a space, at out[at], the list freed:
   how far they reach, or none when one is not a string of printable
   ASCII or they do not fit *)
fun _scopes_put {sz:nat}{l:agz}{at:nat | at <= 1048576} .<sz>.
  (list: $J.json_list(sz), out: !$A.arr(byte, l, 1048576), at: int at): $R.option([stop:nat | stop <= 1048576] int stop) =
  case+ list of
  | ~$J.json_list_nil() => $R.some(at)
  | ~$J.json_list_cons(value, rest) => (case+ value of
    | ~$J.json_str(bytes, length) =>
      if length <= 0 then let
        val () = $A.free<byte>(bytes)
        val () = $J.json_list_free(rest)
      in $R.none() end
      else if ~_printable_bytes(bytes, length, 0) then let
        val () = $A.free<byte>(bytes)
        val () = $J.json_list_free(rest)
      in $R.none() end
      else if at + length + 1 > 1048576 then let
        val () = $A.free<byte>(bytes)
        val () = $J.json_list_free(rest)
      in $R.none() end
      else let
        val () = _copy(bytes, length, out, at, 0)
        val () = $A.free<byte>(bytes)
        val () = $A.set<byte>(out, at + length, int2byte0(32))
      in _scopes_put(rest, out, at + length + 1) end
    | other => let
        val () = $J.json_free(other)
        val () = $J.json_list_free(rest)
      in $R.none() end)

(* A JSON value as the scopes granted: a non-empty list of strings of
   printable ASCII, written separated by spaces *)
fn _scopes_of (value: $J.json_v): $R.option(google_text) =
  case+ value of
  | ~$J.json_arr(list) => let
      val out = $A.alloc<byte>(1048576)
      val stop = _scopes_put(list, out, 0)
    in
      case+ stop of
      | ~$R.some(total) =>
        if total <= 1 then let val () = $A.free<byte>(out) in $R.none() end
        else let
          val copy = $A.alloc<byte>(total - 1)
          val () = _copy(out, total - 1, copy, 0, 0)
          val () = $A.free<byte>(out)
        in $R.some(TextRep(copy, total - 1)) end
      | ~$R.none() => let val () = $A.free<byte>(out) in $R.none() end
    end
  | other => let val () = $J.json_free(other) in $R.none() end

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

(* A rejection JS wrote as JSON *)
fn _rejection (said: google_said): failure =
  case+ _read(said) of
  | ~Refused(error) => FailedOther(RejectionUnparsed(said, error))
  | ~TooLarge() => FailedOther(RejectionTooLarge(_cut(said)))
  | ~Read(value) => (case+ value of
    | ~$J.json_str(bytes, _) => let val () = $A.free<byte>(bytes) in FailedOther(RejectionText(said)) end
    | ~$J.json_obj(entries) => (case+ _take(entries, "code") of
      | ~$R.none() => FailedOther(RejectedOther(said))
      | ~$R.some(code) => (case+ code of
        | ~$J.json_null() => FailedOther(RejectedOther(said))
        | ~$J.json_str(bytes, length) =>
          if _is(bytes, length, "CONSENT_SHOWING") then let
            val () = $A.free<byte>(bytes)
          in FailedConsentShowing(said) end
          else if _is(bytes, length, "UNIMPLEMENTED") then let
            val () = $A.free<byte>(bytes)
          in FailedUnavailable($R.some(said)) end
          else let
            val status = _status_from(bytes, length, StatusServiceVersionUpdateRequired(), 18)
            val () = $A.free<byte>(bytes)
          in
            case+ status of
            | ~$R.some(named) => FailedStatus(named, said)
            | ~$R.none() => FailedOther(RejectedOther(said))
          end
        | other => let val () = $J.json_free(other) in FailedOther(CodeNotText(said)) end))
    | other => let val () = $J.json_free(other) in FailedOther(RejectionNotObject(said)) end)

(* An authorization JS wrote as JSON, decoded: a token, none (the
   authorization is null), or a failure *)
datavtype answer =
  | AnswerToken of (google_text, google_text, $R.option(google_text))
  | AnswerNone of google_said
  | AnswerFailed of failure

(* An authorization object's fields, decoded: in the order JS read
   them before (the token, the scopes, the account) *)
fn _authorized (said: google_said, token: $R.option($J.json_v), scopes: $R.option($J.json_v), account: $R.option($J.json_v)): answer = let
  val token = (case+ token of ~$R.some(v) => _text_of(v) | ~$R.none() => $R.none()): $R.option(google_text)
in
  case+ token of
  | ~$R.none() => let
      val () = _free_value(scopes)
      val () = _free_value(account)
    in AnswerFailed(FailedOther(TokenNotPrintable(said))) end
  | ~$R.some(token) => let
      val scopes = (case+ scopes of ~$R.some(v) => _scopes_of(v) | ~$R.none() => $R.none()): $R.option(google_text)
    in
      case+ scopes of
      | ~$R.none() => let
          val () = google_text_free(token)
          val () = _free_value(account)
        in AnswerFailed(FailedOther(ScopesNotPrintable(said))) end
      | ~$R.some(scopes) => (case+ account of
        | ~$R.none() => let
            val () = google_text_free(token)
            val () = google_text_free(scopes)
          in AnswerFailed(FailedOther(AccountNotPrintable(said))) end
        | ~$R.some(value) => (case+ value of
          | ~$J.json_null() => let val () = google_said_free(said) in AnswerToken(token, scopes, $R.none()) end
          | other => (case+ _text_of(other) of
            | ~$R.some(named) => let val () = google_said_free(said) in AnswerToken(token, scopes, $R.some(named)) end
            | ~$R.none() => let
                val () = google_text_free(token)
                val () = google_text_free(scopes)
              in AnswerFailed(FailedOther(AccountNotPrintable(said))) end)))
    end
end

fn _resolved (said: google_said): answer =
  case+ _read(said) of
  | ~Refused(error) => AnswerFailed(FailedOther(AnswerUnparsed(said, error)))
  | ~TooLarge() => AnswerFailed(FailedOther(AnswerTooLarge(_cut(said))))
  | ~Read(value) => (case+ value of
    | ~$J.json_obj(entries) => (case+ _take(entries, "authorization") of
      | ~$R.none() => AnswerFailed(FailedOther(NoAuthorizationObject(said)))
      | ~$R.some(authorization) => (case+ authorization of
        | ~$J.json_null() => AnswerNone(said)
        | ~$J.json_obj(fields) => let
            val @(token, scopes, account) = _fields(fields, $R.none(), $R.none(), $R.none())
          in _authorized(said, token, scopes, account) end
        | other => let val () = $J.json_free(other) in AnswerFailed(FailedOther(NoAuthorizationObject(said))) end))
    | other => let val () = $J.json_free(other) in AnswerFailed(FailedOther(NoAuthorizationObject(said))) end)

(* The form JS's answer code names: 1 JSON, 2 String, 3 typeof *)
fn _form (number: int): $R.option(google_form) =
  if number = 1 then $R.some(AsJson())
  else if number = 2 then $R.some(AsString())
  else if number = 3 then $R.some(AsType())
  else $R.none()

(* What JS answered, before it is one of an atom's: its answer code (0
   no plugin to call; 1 to 3 resolved, -1 to -3 rejected, 11, 22 or 33
   threw, the answer written as _form says) and the text it kept *)
datavtype answered =
  | NoPlugin
  | Resolved of google_said
  | Rejected of google_said
  | Threw of google_said
  | Odd of (int, $R.option([n:nat] dblob(n)))

fn _answered (number: int, text: $R.option([n:nat] dblob(n))): answered =
  case+ text of
  | ~$R.none() =>
    if number = 0 then NoPlugin() else Odd(number, $R.none())
  | ~$R.some(blob) => let
      val side = (if number > 10 then 3 else if number > 0 then 1 else if number < 0 then 2 else 0): int
      val form = _form(if side = 3 then number / 11 else if side = 2 then 0 - number else number)
    in
      case+ form of
      | ~$R.none() => Odd(number, $R.some(blob))
      | ~$R.some(how) =>
        if side = 3 && number - (number / 11) * 11 <> 0 then Odd(number, $R.some(blob))
        else if side = 1 then Resolved(GoogleSaid(how, blob))
        else if side = 2 then Rejected(GoogleSaid(how, blob))
        else if side = 3 then Threw(GoogleSaid(how, blob))
        else Odd(number, $R.some(blob))
    end

(* An authorization's answer *)
fn _answer (answered: answered): answer =
  case+ answered of
  | ~NoPlugin() => AnswerFailed(FailedUnavailable($R.none()))
  | ~Resolved(said) => (case+ said of
    | GoogleSaid(AsJson(), _) => _resolved(said)
    | _ => AnswerFailed(FailedOther(AnswerNotJson(said))))
  | ~Rejected(said) => (case+ said of
    | GoogleSaid(AsJson(), _) => AnswerFailed(_rejection(said))
    | _ => AnswerFailed(FailedOther(RejectionNotJson(said))))
  | ~Threw(said) => AnswerFailed(FailedOther(DecodeThrew(said)))
  | ~Odd(number, said) => AnswerFailed(FailedOther(OddAnswer(number, said)))

(* A failure of authorizationForScopes: it shows no consent screen, so
   CONSENT_SHOWING is a code it does not document *)
fn _found_failure (failure: failure): google_authorization(Silently) =
  case+ failure of
  | ~FailedStatus(status, said) => AuthorizeRefused(status, said)
  | ~FailedConsentShowing(said) => AuthorizeUnexpected(RejectedOther(said))
  | ~FailedUnavailable(said) => AuthorizeUnavailable(said)
  | ~FailedOther(unexpected) => AuthorizeUnexpected(unexpected)

(* authorizationForScopes' answer: Play services' CANCELED from it
   (it shows nothing to cancel) is a refusal like any other status *)
fn _found (answer: answer): google_authorization(Silently) =
  case+ answer of
  | ~AnswerToken(token, scopes, account) => Authorized(token, scopes, account)
  | ~AnswerNone(said) => let val () = google_said_free(said) in NotAuthorized() end
  | ~AnswerFailed(failure) => _found_failure(failure)

(* authorizeScopes' answer: it always gives an authorization when it
   resolves, so a null one is unexpected; CANCELED, decoded here alone,
   is AuthorizeCanceled: the plugin's code for the reader backing out,
   which a CANCELED status Play services gives before any consent
   screen shares (bats-lang/capacitor-plugins#8) *)
fn _asked (answer: answer): google_authorization(MayAsk) =
  case+ answer of
  | ~AnswerToken(token, scopes, account) => Authorized(token, scopes, account)
  | ~AnswerNone(said) => AuthorizeUnexpected(NoAuthorizationObject(said))
  | ~AnswerFailed(failure) => (case+ failure of
    | ~FailedStatus(status, said) => (case+ status of
      | StatusCanceled() => AuthorizeCanceled(said)
      | _ =>> AuthorizeRefused(status, said))
    | ~FailedConsentShowing(said) => ConsentShowing(said)
    | ~FailedUnavailable(said) => AuthorizeUnavailable(said)
    | ~FailedOther(unexpected) => AuthorizeUnexpected(unexpected))

(* clearAuthorizationToken's and revokeAccess': resolved, whatever with,
   is done; neither shows a consent screen *)
fn _change (answered: answered): google_authorization_change = let
  fn failed (failure: failure): google_authorization_change =
    case+ failure of
    | ~FailedStatus(status, said) => ChangeRefused(status, said)
    | ~FailedConsentShowing(said) => ChangeUnexpected(RejectedOther(said))
    | ~FailedUnavailable(said) => ChangeUnavailable(said)
    | ~FailedOther(unexpected) => ChangeUnexpected(unexpected)
in
  case+ answered of
  | ~NoPlugin() => ChangeUnavailable($R.none())
  | ~Resolved(said) => let val () = google_said_free(said) in Changed() end
  | ~Rejected(said) => (case+ said of
    | GoogleSaid(AsJson(), _) => failed(_rejection(said))
    | _ => ChangeUnexpected(RejectionNotJson(said)))
  | ~Threw(said) => ChangeUnexpected(DecodeThrew(said))
  | ~Odd(number, said) => ChangeUnexpected(OddAnswer(number, said))
end

fn {} _free_authorization {w:asking} (answer: google_authorization(w)): void =
  case+ answer of
  | ~Authorized(token, scopes, account) => let
      val () = google_text_free(token)
      val () = google_text_free(scopes)
    in case+ account of ~$R.some(named) => google_text_free(named) | ~$R.none() => () end
  | ~NotAuthorized() => ()
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

implement google_authorize_available() = _bats_js_google_authorize_available() > 0

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

(* Asks JS, may_ask 0 for authorizationForScopes and 1 for
   authorizeScopes; resolves with the resolver's id and JS's code *)
fn _ask {t:pos | t <= 1048576} (scopes: google_scopes(t), may_ask: int)
  : @(int, $P.promise(Int, $P.Pending)) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val stop = _scopes_bytes(scopes)
  val out = $A.alloc<byte>(stop)
  val () = _scopes_put(scopes, out, 0)
  val @(frozen, borrowed) = $A.freeze<byte>(out)
  val () = _bats_js_google_authorize(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(borrowed) end, stop, may_ask, id)
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in @(id, p) end

implement google_authorization_for_scopes{t}(scopes) = let
  val @(id, p) = _ask(scopes, 0)
in $P.and_then<Int><google_authorization(Silently)>(p, llam (code) =>
  $P.ret<google_authorization(Silently)>(_found(_answer(_answered(code, _text(id)))))) end

implement google_authorize_scopes{t}(scopes) = let
  val @(id, p) = _ask(scopes, 1)
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
