#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use json as J
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload GZ = "wasm.bats-packages.dev/bridge/src/google_authorize.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"

(* Answers nobody took, freed: before their first use *)
fn free_said (said: $R.option($GZ.google_said)): void =
  case+ said of ~$R.some(kept) => $GZ.google_said_free(kept) | ~$R.none() => ()

fn free_authorization {w:$GZ.asking} (answer: $GZ.google_authorization(w)): void =
  case+ answer of
  | ~$GZ.Authorized(token, scopes, account) => let
      val () = $GZ.google_text_free(token)
      val () = $GZ.google_text_free(scopes)
    in case+ account of ~$R.some(named) => $GZ.google_text_free(named) | ~$R.none() => () end
  | ~$GZ.NotAuthorized() => ()
  | ~$GZ.AuthorizeCanceled(said) => $GZ.google_said_free(said)
  | ~$GZ.ConsentShowing(said) => $GZ.google_said_free(said)
  | ~$GZ.AuthorizeRefused(_, said) => $GZ.google_said_free(said)
  | ~$GZ.AuthorizeUnavailable(said) => free_said(said)
  | ~$GZ.AuthorizeUnexpected(unexpected) => $GZ.google_unexpected_free(unexpected)

fn free_change (change: $GZ.google_authorization_change): void =
  case+ change of
  | ~$GZ.Changed() => ()
  | ~$GZ.ChangeRefused(_, said) => $GZ.google_said_free(said)
  | ~$GZ.ChangeUnavailable(said) => free_said(said)
  | ~$GZ.ChangeUnexpected(unexpected) => $GZ.google_unexpected_free(unexpected)

implement $P.dispose<$GZ.google_authorization($GZ.Silently)>(answer) = free_authorization(answer)
implement $P.dispose<$GZ.google_authorization($GZ.MayAsk)>(answer) = free_authorization(answer)
implement $P.dispose<$GZ.google_authorization_change>(change) = free_change(change)

(* ------------------------------------------------------------
   The hash: each line check.mjs prints is one hash, numbered, so no
   two are the same and each fires hashchange
   ------------------------------------------------------------ *)

val line_number = ref<int>(0)

(* out[at, at + count): n's last count digits, its sign aside *)
fun digits_put {l:agz}{size:nat}{at:nat}{count:nat | at + count <= size} .<count>.
  (out: !$A.arr(byte, l, size), at: int at, count: int count, n: int): void =
  if count <= 0 then ()
  else let
    val rest = n - (n / 10) * 10
    val digit = (if rest < 0 then 0 - rest else rest): int
    val () = $A.set<byte>(out, at + count - 1, int2byte0(48 + digit))
  in digits_put(out, at, count - 1, n / 10) end

(* out[to + j, to + count) := from[j, count) *)
fun copy_into {l,c:agz}{size,total:nat}{count:nat | count <= size}{to:nat | to + count <= total}{j:nat | j <= count} .<count - j>.
  (from: !$A.arr(byte, l, size), count: int count, out: !$A.arr(byte, c, total), to: int to, j: int j): void =
  if j >= count then ()
  else let
    val () = $A.set<byte>(out, to + j, $A.get<byte>(from, j))
  in copy_into(from, count, out, to, j + 1) end

(* The hash set to the next line's number, a space, then a[0, n) *)
fn hash_bytes {l:agz}{size:nat}{n:nat | n <= size; n <= 4096} (a: $A.arr(byte, l, size), n: int n): void = let
  val number = !line_number
  val () = !line_number := number + 1
  val out = $A.alloc<byte>(n + 6)
  val () = digits_put(out, 0, 5, number)
  val () = $A.set<byte>(out, 5, int2byte0(32))
  val () = copy_into(a, n, out, 6, 0)
  val () = $A.free<byte>(a)
  val @(frozen, borrowed) = $A.freeze<byte>(out)
  val () = $NAV.set_hash(borrowed, n + 6)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn bytes {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

fn hash_text {n:pos | n < 256} (s: string n): void =
  hash_bytes(bytes(s), g1u2i(string1_length(s)))

(* n in decimal, after its sign *)
fn hash_number (n: int): void = let
  val out = $A.alloc<byte>(12)
  val () = $A.set<byte>(out, 0, int2byte0(if n < 0 then 45 else 43))
  val () = digits_put(out, 1, 11, n)
in hash_bytes(out, 12) end

(* A blob's text when it is at most 300 bytes, else its length and its
   first 300: a hash is one line of check.mjs's output *)
fn hash_blob {n:nat} (blob: !$BD.dblob(n)): void = let
  val n = $BD.blob_len(blob)
in
  if n <= 0 then hash_text("(empty)")
  else if n <= 300 then let
    val copy = $A.alloc<byte>(n)
    val () = $BD.blob_read(blob, 0, copy, n)
  in hash_bytes(copy, n) end
  else let
    val () = hash_text("long, bytes:")
    val () = hash_number(n)
    val copy = $A.alloc<byte>(300)
    val () = $BD.blob_read(blob, 0, copy, 300)
  in hash_bytes(copy, 300) end
end

fn hash_form (form: $GZ.google_form): void =
  case+ form of
  | $GZ.AsJson() => hash_text("as JSON")
  | $GZ.AsString() => hash_text("as String")
  | $GZ.AsType() => hash_text("as its type")

(* What the plugin answered, as JS wrote it: its form, then its text *)
(* json's error: its name, then where *)
fn hash_parse_error (error: $J.parse_error): void =
  case+ error of
  | ~$J.UnexpectedEnd(at) => let val () = hash_text("UnexpectedEnd") in hash_number(at) end
  | ~$J.UnexpectedByte(at) => let val () = hash_text("UnexpectedByte") in hash_number(at) end
  | ~$J.BadNumber(at) => let val () = hash_text("BadNumber") in hash_number(at) end
  | ~$J.NumberTooLong(at) => let val () = hash_text("NumberTooLong") in hash_number(at) end
  | ~$J.StringTooLong(at) => let val () = hash_text("StringTooLong") in hash_number(at) end
  | ~$J.ControlInString(at) => let val () = hash_text("ControlInString") in hash_number(at) end
  | ~$J.BadEscape(at) => let val () = hash_text("BadEscape") in hash_number(at) end
  | ~$J.BadHex(at) => let val () = hash_text("BadHex") in hash_number(at) end
  | ~$J.InvalidUtf8(at) => let val () = hash_text("InvalidUtf8") in hash_number(at) end
  | ~$J.TooDeep(at) => let val () = hash_text("TooDeep") in hash_number(at) end
  | ~$J.TrailingData(at) => let val () = hash_text("TrailingData") in hash_number(at) end

fn hash_said (said: $GZ.google_said): void = let
  val ~$GZ.GoogleSaid(form, text) = said
  val () = hash_form(form)
  val () = hash_blob(text)
in $BD.blob_free(text) end

fn hash_cut (cut: $GZ.google_cut): void = let
  val ~$GZ.GoogleCut(form, total, first) = cut
  val () = hash_form(form)
  val () = hash_text("cut, whole length:")
  val () = hash_number(total)
in hash_bytes(first, 300) end

fn hash_status (status: $GZ.google_status): void = let
  val () = hash_text($GZ.google_status_name(status))
in hash_number($GZ.google_status_number(status)) end

fn hash_unexpected (unexpected: $GZ.google_unexpected): void = let
  val () = hash_text("unexpected")
in
  case+ unexpected of
  | ~$GZ.AnswerNotJson(said) => let val () = hash_text("answer not JSON") in hash_said(said) end
  | ~$GZ.AnswerUnparsed(said, error) => let val () = hash_text("answer unparsed") val () = hash_parse_error(error) in hash_said(said) end
  | ~$GZ.AnswerTooLarge(cut) => let val () = hash_text("answer too large") in hash_cut(cut) end
  | ~$GZ.NoAuthorizationObject(said) => let val () = hash_text("no authorization object") in hash_said(said) end
  | ~$GZ.TokenNotPrintable(said) => let val () = hash_text("token not printable") in hash_said(said) end
  | ~$GZ.ScopesNotPrintable(said) => let val () = hash_text("scopes not printable") in hash_said(said) end
  | ~$GZ.AccountNotPrintable(said) => let val () = hash_text("account not printable") in hash_said(said) end
  | ~$GZ.RejectionNotJson(said) => let val () = hash_text("rejection not JSON") in hash_said(said) end
  | ~$GZ.RejectionUnparsed(said, error) => let val () = hash_text("rejection unparsed") val () = hash_parse_error(error) in hash_said(said) end
  | ~$GZ.RejectionTooLarge(cut) => let val () = hash_text("rejection too large") in hash_cut(cut) end
  | ~$GZ.RejectionText(said) => let val () = hash_text("rejection text") in hash_said(said) end
  | ~$GZ.RejectionNotObject(said) => let val () = hash_text("rejection not object") in hash_said(said) end
  | ~$GZ.CodeNotText(said) => let val () = hash_text("code not text") in hash_said(said) end
  | ~$GZ.RejectedOther(said) => let val () = hash_text("rejected other") in hash_said(said) end
  | ~$GZ.DecodeThrew(said) => let val () = hash_text("decode threw") in hash_said(said) end
  | ~$GZ.OddAnswer(number, said) => let
      val () = hash_text("odd answer")
      val () = hash_number(number)
    in
      case+ said of
      | ~$R.some(blob) => let val () = hash_blob(blob) in $BD.blob_free(blob) end
      | ~$R.none() => hash_text("no text")
    end
end

fn hash_unavailable (said: $R.option($GZ.google_said)): void = let
  val () = hash_text("unavailable")
in case+ said of ~$R.some(kept) => hash_said(kept) | ~$R.none() => hash_text("no plugin") end

fn hash_google_text (text: $GZ.google_text): void = let
  val @(a, n) = $GZ.google_text_bytes(text)
in
  if n <= 300 then hash_bytes(a, n)
  else let val () = $A.free<byte>(a) in hash_text("(a text over 300 bytes)") end
end

(* ------------------------------------------------------------
   The calls
   ------------------------------------------------------------ *)

vtypedef step = $P.promise($GZ.google_authorization_change, $P.Chained)

fn done (): step = $P.ret<$GZ.google_authorization_change>($GZ.Changed())

(* How a clear or a revoke ended, in the hash *)
fn told_change (change: $GZ.google_authorization_change): step =
  case+ change of
  | ~$GZ.Changed() => let val () = hash_text("changed") in done() end
  | ~$GZ.ChangeRefused(status, said) => let
      val () = hash_text("refused")
      val () = hash_status(status)
      val () = hash_said(said)
    in done() end
  | ~$GZ.ChangeUnavailable(said) => let val () = hash_unavailable(said) in done() end
  | ~$GZ.ChangeUnexpected(unexpected) => let val () = hash_unexpected(unexpected) in done() end

(* The scope the app asks for: drive.appdata, checked once *)
fn drive_appdata_scope (): $R.option($GZ.google_scope(45)) =
  $GZ.google_scope_of("https://www.googleapis.com/auth/drive.appdata")

fn text_of {n:pos | n < 256} (s: string n): $R.option($GZ.google_text) = let
  val n = g1u2i(string1_length(s))
  val a = bytes(s)
  val @(frozen, borrowed) = $A.freeze<byte>(a)
  val text = $GZ.google_text_of(borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in text end

fn clear (token: $GZ.google_text): step = let
  val () = hash_text("clear")
in $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>($GZ.google_clear_token(token), llam(change) => told_change(change)) end

fn revoke (account: $GZ.google_text): step = let
  val () = hash_text("revoke")
in
  case+ drive_appdata_scope() of
  | ~$R.some(scope) =>
    $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>($GZ.google_revoke_access(account, $GZ.OneScope(scope)), llam(change) => told_change(change))
  | ~$R.none() => let
      val () = $GZ.google_text_free(account)
      val () = hash_text("not a scope")
    in done() end
end

(* An authorization: its scopes and account in the hash, then the token
   cleared and the account's grant revoked, so the plugin prints the
   token and the account as they came back *)
fn told_authorized (token: $GZ.google_text, scopes: $GZ.google_text, account: $R.option($GZ.google_text)): step = let
  val () = hash_text("authorized")
  val () = hash_google_text(scopes)
in
  case+ account of
  | ~$R.none() => let
      val () = hash_text("no account")
    in clear(token) end
  | ~$R.some(named) =>
    $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(clear(token), llam(change) => let
      val () = free_change(change) in revoke(named) end)
end

fn told_found (answer: $GZ.google_authorization($GZ.Silently)): step =
  case+ answer of
  | ~$GZ.Authorized(token, scopes, account) => told_authorized(token, scopes, account)
  | ~$GZ.NotAuthorized() => let val () = hash_text("not authorized") in done() end
  | ~$GZ.AuthorizeRefused(status, said) => let
      val () = hash_text("refused")
      val () = hash_status(status)
      val () = hash_said(said)
    in done() end
  | ~$GZ.AuthorizeUnavailable(said) => let val () = hash_unavailable(said) in done() end
  | ~$GZ.AuthorizeUnexpected(unexpected) => let val () = hash_unexpected(unexpected) in done() end

fn told_asked (answer: $GZ.google_authorization($GZ.MayAsk)): step =
  case+ answer of
  | ~$GZ.Authorized(token, scopes, account) => told_authorized(token, scopes, account)
  | ~$GZ.AuthorizeCanceled(said) => let
      val () = hash_text("canceled")
      val () = hash_said(said)
    in done() end
  | ~$GZ.ConsentShowing(said) => let
      val () = hash_text("consent showing")
      val () = hash_said(said)
    in done() end
  | ~$GZ.AuthorizeRefused(status, said) => let
      val () = hash_text("refused")
      val () = hash_status(status)
      val () = hash_said(said)
    in done() end
  | ~$GZ.AuthorizeUnavailable(said) => let val () = hash_unavailable(said) in done() end
  | ~$GZ.AuthorizeUnexpected(unexpected) => let val () = hash_unexpected(unexpected) in done() end

fn found (): step =
  case+ drive_appdata_scope() of
  | ~$R.none() => let val () = hash_text("not a scope") in done() end
  | ~$R.some(scope) => let
      val () = hash_text("authorization for scopes")
    in $P.and_then<$GZ.google_authorization($GZ.Silently)><$GZ.google_authorization_change>($GZ.google_authorization_for_scopes($GZ.OneScope(scope)), llam(answer) => told_found(answer)) end

(* drive.appdata listed twice, so the plugin prints a list of two *)
fn found_twice (): step =
  case+ drive_appdata_scope() of
  | ~$R.none() => let val () = hash_text("not a scope") in done() end
  | ~$R.some(scope) => let
      val () = hash_text("authorization for scopes")
    in $P.and_then<$GZ.google_authorization($GZ.Silently)><$GZ.google_authorization_change>($GZ.google_authorization_for_scopes($GZ.MoreScopes(scope, $GZ.OneScope(scope))), llam(answer) => told_found(answer)) end

fn asked (): step =
  case+ drive_appdata_scope() of
  | ~$R.none() => let val () = hash_text("not a scope") in done() end
  | ~$R.some(scope) => let
      val () = hash_text("authorize scopes")
    in $P.and_then<$GZ.google_authorization($GZ.MayAsk)><$GZ.google_authorization_change>($GZ.google_authorize_scopes($GZ.OneScope(scope)), llam(answer) => told_asked(answer)) end

fn queued_clear (): step =
  case+ text_of("queued-token") of
  | ~$R.some(token) => clear(token)
  | ~$R.none() => let val () = hash_text("not a token") in done() end

fn queued_revoke (): step =
  case+ text_of("queued@example.com") of
  | ~$R.some(account) => revoke(account)
  | ~$R.none() => let val () = hash_text("not an account") in done() end

(* Whether text is a scope: y or n at out[at] *)
fn scope_case {l:agz}{at:nat | at < 4}{n:pos | n < 256} (out: !$A.arr(byte, l, 4), at: int at, text: string n): void =
  case+ $GZ.google_scope_of(text) of
  | ~$R.some(_) => $A.set<byte>(out, at, int2byte0(121))
  | ~$R.none() => $A.set<byte>(out, at, int2byte0(110))

(* A scope is printable ASCII: y or n for two scopes with a space
   between, a tab, a letter outside ASCII, then drive.appdata's *)
fn split_scope (): void = let
  val out = $A.alloc<byte>(4)
  val () = scope_case(out, 0, "scope-a scope-b")
  val () = scope_case(out, 1, "scope-a\tscope-b")
  val () = scope_case(out, 2, "scope-\303\251")
  val () = scope_case(out, 3, "https://www.googleapis.com/auth/drive.appdata")
in hash_bytes(out, 4) end

(* A token or account that is not printable ASCII is no google_text *)
fn texts (): void = let
  val () = (case+ text_of("a b") of
    | ~$R.some(t) => let val () = $GZ.google_text_free(t) in hash_text("a b: a text") end
    | ~$R.none() => hash_text("a b: none"))
in
  case+ text_of("a\377b") of
  | ~$R.some(t) => let val () = $GZ.google_text_free(t) in hash_text("a, 0xFF, b: a text") end
  | ~$R.none() => hash_text("a, 0xFF, b: none")
end

datatype call = Found | Asked | QueuedClear | QueuedRevoke

fn call_step (call: call): step =
  case+ call of
  | Found() => found()
  | Asked() => asked()
  | QueuedClear() => queued_clear()
  | QueuedRevoke() => queued_revoke()

(* call left times, one after another, after first *)
fun times {left:nat} .<left>. (first: step, call: call, left: int left): step =
  if left <= 0 then first
  else times($P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(first, llam(change) => let
    val () = free_change(change) in call_step(call) end), call, left - 1)

(* check.mjs plays the plugin, its answers queued per method in the
   order of these calls, and a browser with no Capacitor. The counts
   are check.mjs's queues' lengths, which it checks *)
#define SILENT 400
#define PROMPTING 80
#define CLEARS 80
#define REVOKES 80

implement main0 () = let
  val () = (if $GZ.google_authorize_available() then hash_text("available") else hash_text("unavailable"))
  val () = split_scope()
  val () = texts()
  val s = times(found_twice(), Found(), SILENT - 1)
  val s = times(s, Asked(), PROMPTING)
  val s = times(s, QueuedClear(), CLEARS)
  val s = times(s, QueuedRevoke(), REVOKES)
in $P.finish<$GZ.google_authorization_change>(s, llam(change) => free_change(change)) end
