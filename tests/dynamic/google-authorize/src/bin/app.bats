#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload GZ = "wasm.bats-packages.dev/bridge/src/google_authorize.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"

(* Answers nobody took, freed: before their first use *)
fn {} free_part (part: $R.option([n:pos] $BD.dblob(n))): void =
  case+ part of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ()

fn {} free_authorization {w:$GZ.asking} (answer: $GZ.google_authorization(w)): void =
  case+ answer of
  | ~$GZ.Authorized(token, scopes, account) => let
      val () = $BD.blob_free(token)
      val () = $BD.blob_free(scopes)
    in free_part(account) end
  | ~$GZ.NotAuthorized() => ()
  | ~$GZ.AuthorizeCanceled() => ()
  | ~$GZ.ConsentShowing() => ()
  | ~$GZ.AuthorizeRefused(_, message) => free_part(message)
  | ~$GZ.AuthorizeUnavailable() => ()
  | ~$GZ.AuthorizeUnexpected(code, message) => let val () = free_part(code) in free_part(message) end

implement $P.dispose<$GZ.google_authorization($GZ.Silently)>(answer) = free_authorization(answer)
implement $P.dispose<$GZ.google_authorization($GZ.MayAsk)>(answer) = free_authorization(answer)
implement $P.dispose<$GZ.google_authorization_change>(change) =
  case+ change of
  | ~$GZ.Changed() => ()
  | ~$GZ.ChangeRefused(_, message) => free_part(message)
  | ~$GZ.ChangeUnavailable() => ()
  | ~$GZ.ChangeUnexpected(code, message) => let val () = free_part(code) in free_part(message) end

(* s's bytes in a fresh array of exactly its length *)
fn bytes {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

(* A blob's bytes in a fresh array, when it is at most 4096 bytes; the
   blob is freed *)
fn copied {k:pos} (blob: $BD.dblob(k)): [l:agz][n:pos] @($A.arr(byte, l, n), int n) = let
  val k = $BD.blob_len(blob)
in
  if k > 4096 then let
    val () = $BD.blob_free(blob)
    val note = bytes("too long")
  in @(note, 8) end
  else let
    val copy = $A.alloc<byte>(k)
    val () = $BD.blob_read(blob, 0, copy, k)
    val () = $BD.blob_free(blob)
  in @(copy, k) end
end

(* The page's hash set to a[0, n), which check.mjs prints *)
fn hash_bytes {l:agz}{n:nat} (a: $A.arr(byte, l, n), n: int n): void = let
  val @(frozen, borrowed) = $A.freeze<byte>(a)
  val () = $NAV.set_hash(borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn hash_text {n:pos | n < 256} (s: string n): void =
  hash_bytes(bytes(s), g1u2i(string1_length(s)))

(* A failure's code in the hash, or "no code" *)
fn hash_code (code: $R.option([n:pos] $BD.dblob(n))): void =
  case+ code of
  | ~$R.some(blob) => let
      val @(a, n) = copied(blob)
    in hash_bytes(a, n) end
  | ~$R.none() => hash_text("no code")

(* A failure's message in the hash, or "no message" *)
fn hash_message (message: $R.option([n:pos] $BD.dblob(n))): void =
  case+ message of
  | ~$R.some(blob) => let
      val @(a, n) = copied(blob)
    in hash_bytes(a, n) end
  | ~$R.none() => hash_text("no message")

(* A status Play services named: "refused", its name and number, then
   its message, each in the hash *)
fn hash_refused (status: $GZ.google_status, message: $R.option([n:pos] $BD.dblob(n))): void = let
  val () = hash_text("refused")
  val () = hash_text($GZ.google_status_name(status))
  val number = $GZ.google_status_number(status)
  val digits = $A.alloc<byte>(2)
  val () = $A.set<byte>(digits, 0, int2byte0(48 + number / 10))
  val () = $A.set<byte>(digits, 1, int2byte0(48 + number - (number / 10) * 10))
  val () = hash_bytes(digits, 2)
in hash_message(message) end

(* An answer not recognised: "unexpected", its code, then its message *)
fn hash_unexpected (code: $R.option([n:pos] $BD.dblob(n)), message: $R.option([n:pos] $BD.dblob(n))): void = let
  val () = hash_text("unexpected")
  val () = hash_code(code)
in hash_message(message) end

vtypedef step = $P.promise($GZ.google_authorization_change, $P.Chained)

(* A step that does nothing more *)
fn done (): step = $P.ret<$GZ.google_authorization_change>($GZ.Changed())

(* How a clear or a revoke ended, in the hash *)
fn told_change (change: $GZ.google_authorization_change): step =
  case+ change of
  | ~$GZ.Changed() => let val () = hash_text("changed") in done() end
  | ~$GZ.ChangeRefused(status, message) => let val () = hash_refused(status, message) in done() end
  | ~$GZ.ChangeUnavailable() => let val () = hash_text("unavailable") in done() end
  | ~$GZ.ChangeUnexpected(code, message) => let val () = hash_unexpected(code, message) in done() end

(* a's bytes as a google_text, a freed; none when they hold no visible
   character (or are too long to be one) *)
fn text_of {l:agz}{n:pos} (a: $A.arr(byte, l, n), n: int n): $R.option($GZ.google_text) =
  if n > 4096 then let val () = $A.free<byte>(a) in $R.none() end
  else let
    val @(frozen, borrowed) = $A.freeze<byte>(a)
    val text = $GZ.google_text_of(borrowed, n)
    val () = $A.drop<byte>(frozen, borrowed)
    val () = $A.free<byte>($A.thaw<byte>(frozen))
  in text end

fn clear_bytes {l:agz}{n:pos} (a: $A.arr(byte, l, n), n: int n): step =
  case+ text_of(a, n) of
  | ~$R.none() => let val () = hash_text("not a token") in done() end
  | ~$R.some(token) =>
    $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>($GZ.google_clear_token(token), llam(change) => told_change(change))

(* Clears the token s *)
fn clear_text {n:pos | n < 256} (s: string n): step = let
  val () = hash_text("clear")
in clear_bytes(bytes(s), g1u2i(string1_length(s))) end

(* The scope the app asks for: drive.appdata, checked once *)
fn drive_appdata_scope (): $R.option($GZ.google_scope) =
  $GZ.google_scope_of("https://www.googleapis.com/auth/drive.appdata")

(* Revokes the account's grant of drive.appdata *)
fn revoke {la:agz}{na:pos}
  (account: $A.arr(byte, la, na), account_len: int na): step = let
  val () = hash_text("revoke")
in
  case+ text_of(account, account_len) of
  | ~$R.none() => let val () = hash_text("not an account") in done() end
  | ~$R.some(text) => (case+ drive_appdata_scope() of
    | ~$R.some(scope) =>
      $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>($GZ.google_revoke_access(text, $GZ.OneScope(scope)), llam(change) => told_change(change))
    | ~$R.none() => let
        val () = $GZ.google_text_free(text)
        val () = hash_text("not a scope")
      in done() end)
end

(* Revokes account s's grant of drive.appdata *)
fn revoke_text {n:pos | n < 256} (s: string n): step =
  revoke(bytes(s), g1u2i(string1_length(s)))

(* An authorization given: "authorized" in the hash, then its token
   cleared and, when it names an account and its scopes, the account's
   grant of them revoked, so the plugin prints what came back *)
fn told_authorized {k:pos}{g:pos}
  (token: $BD.dblob(k), scopes: $BD.dblob(g), account: $R.option([n:pos] $BD.dblob(n))): step = let
  val () = hash_text("authorized")
  val @(token_bytes, token_len) = copied(token)
  val cleared = clear_bytes(token_bytes, token_len)
  (* the scopes granted, in the hash *)
  val @(scopes_bytes, scopes_len) = copied(scopes)
  val () = hash_bytes(scopes_bytes, scopes_len)
in
  case+ account of
  | ~$R.none() => let
      val () = hash_text("no account")
    in cleared end
  | ~$R.some(account) => let
      val @(account_bytes, account_len) = copied(account)
    in $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(cleared, llam(_) =>
      revoke(account_bytes, account_len)) end
end

fn told_found (answer: $GZ.google_authorization($GZ.Silently)): step =
  case+ answer of
  | ~$GZ.Authorized(token, scopes, account) => told_authorized(token, scopes, account)
  | ~$GZ.NotAuthorized() => let val () = hash_text("not authorized") in done() end
  | ~$GZ.AuthorizeRefused(status, message) => let val () = hash_refused(status, message) in done() end
  | ~$GZ.AuthorizeUnavailable() => let val () = hash_text("unavailable") in done() end
  | ~$GZ.AuthorizeUnexpected(code, message) => let val () = hash_unexpected(code, message) in done() end

fn told_asked (answer: $GZ.google_authorization($GZ.MayAsk)): step =
  case+ answer of
  | ~$GZ.Authorized(token, scopes, account) => told_authorized(token, scopes, account)
  | ~$GZ.AuthorizeCanceled() => let val () = hash_text("canceled") in done() end
  | ~$GZ.ConsentShowing() => let val () = hash_text("consent showing") in done() end
  | ~$GZ.AuthorizeRefused(status, message) => let val () = hash_refused(status, message) in done() end
  | ~$GZ.AuthorizeUnavailable() => let val () = hash_text("unavailable") in done() end
  | ~$GZ.AuthorizeUnexpected(code, message) => let val () = hash_unexpected(code, message) in done() end

(* Asks for drive.appdata with no UI *)
fn found (): step =
  case+ drive_appdata_scope() of
  | ~$R.none() => let val () = hash_text("not a scope") in done() end
  | ~$R.some(scope) => let
      val () = hash_text("authorization for scopes")
      val asked = $GZ.google_authorization_for_scopes($GZ.OneScope(scope))
    in $P.and_then<$GZ.google_authorization($GZ.Silently)><$GZ.google_authorization_change>(asked, llam(answer) => told_found(answer)) end

(* Asks for drive.appdata twice with no UI (two scopes, so the plugin
   prints them as a list) *)
fn found_twice (): step =
  case+ drive_appdata_scope() of
  | ~$R.none() => let val () = hash_text("not a scope") in done() end
  | ~$R.some(scope) => let
      val () = hash_text("authorization for scopes")
      val asked = $GZ.google_authorization_for_scopes($GZ.MoreScopes(scope, $GZ.OneScope(scope)))
    in $P.and_then<$GZ.google_authorization($GZ.Silently)><$GZ.google_authorization_change>(asked, llam(answer) => told_found(answer)) end

(* Asks for drive.appdata, a consent screen allowed *)
fn asked (): step =
  case+ drive_appdata_scope() of
  | ~$R.none() => let val () = hash_text("not a scope") in done() end
  | ~$R.some(scope) => let
      val () = hash_text("authorize scopes")
      val asked = $GZ.google_authorize_scopes($GZ.OneScope(scope))
    in $P.and_then<$GZ.google_authorization($GZ.MayAsk)><$GZ.google_authorization_change>(asked, llam(answer) => told_asked(answer)) end

(* Whether text is a scope: y or n at out[at] *)
fn scope_case {l:agz}{at:nat | at < 10}{n:pos | n < 256} (out: !$A.arr(byte, l, 10), at: int at, text: string n): void =
  case+ $GZ.google_scope_of(text) of
  | ~$R.some(_) => $A.set<byte>(out, at, int2byte0(121))
  | ~$R.none() => $A.set<byte>(out, at, int2byte0(110))

(* Only a scope-token is a scope: no whitespace of any kind, no quote or
   backslash, nothing non-ASCII. One hash, "scopes " and a y or n for
   each of: a space, a tab, a line feed, a carriage return, a form feed,
   a vertical tab, an ideographic space, a quote, a backslash, then
   drive.appdata's scope *)
fn split_scope (): void = let
  val out = $A.alloc<byte>(10)
  val () = scope_case(out, 0, "scope-a scope-b")
  val () = scope_case(out, 1, "scope-a\tscope-b")
  val () = scope_case(out, 2, "scope-a\nscope-b")
  val () = scope_case(out, 3, "scope-a\rscope-b")
  val () = scope_case(out, 4, "scope-a\014scope-b")
  val () = scope_case(out, 5, "\013")
  val () = scope_case(out, 6, "\343\200\200")
  val () = scope_case(out, 7, "scope\"a")
  val () = scope_case(out, 8, "scope\\a")
  val () = scope_case(out, 9, "https://www.googleapis.com/auth/drive.appdata")
in hash_bytes(out, 10) end

(* A step's end, read: nothing to do with it but let it go *)
fn ended (change: $GZ.google_authorization_change): void =
  case+ change of
  | ~$GZ.Changed() => ()
  | ~$GZ.ChangeRefused(_, message) => free_part(message)
  | ~$GZ.ChangeUnavailable() => ()
  | ~$GZ.ChangeUnexpected(code, message) => let val () = free_part(code) in free_part(message) end

(* Asks for scope-a with no UI left times, one after another *)
fun found_times {left:pos} .<left>. (left: int left): step =
  if left <= 1 then found()
  else $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(found(), llam(change) => let
    val () = ended(change) in found_times(left - 1) end)

(* check.mjs plays the native app with the GoogleAuthorize plugin, whose
   answers come in the order of the calls below, and a browser (no
   Capacitor). Each call is named in the hash, then its answer; an authorization's token
   is cleared and its account's grant of its scopes revoked, so the
   plugin prints them as they came back *)
implement main0 () = let
  val () = (if $GZ.google_authorize_available() then hash_text("available") else hash_text("unavailable"))
  (* a scope with whitespace in it is refused as it is made *)
  val () = split_scope()
  (* granted, with an account *)
  val s1 = found_twice()
  (* consent needed *)
  val s2 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s1, llam(change) => let
    val () = ended(change) in found() end)
  (* Play services refused, with its status *)
  val s3 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s2, llam(change) => let
    val () = ended(change) in found() end)
  (* refused with no code: unexpected *)
  val s4 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s3, llam(change) => let
    val () = ended(change) in found() end)
  (* the plugin's UNEXPECTED *)
  val s5 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s4, llam(change) => let
    val () = ended(change) in found() end)
  (* a code nothing documents *)
  val s6 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s5, llam(change) => let
    val () = ended(change) in found() end)
  (* CONSENT_SHOWING, which authorizationForScopes never answers *)
  val s7 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s6, llam(change) => let
    val () = ended(change) in found() end)
  (* Play services' CANCELED, which authorizationForScopes shows nothing to
     cancel: a refusal *)
  val s7b = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s7, llam(change) => let
    val () = ended(change) in found() end)
  (* every other status Play services names, then SUCCESS, which is no
     refusal: 15 asks *)
  val s7c = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s7b, llam(change) => let
    val () = ended(change) in found_times(15) end)
  (* answers authorizationForScopes does not document: no authorization,
     a blank token, no scope granted, an account that is empty, not a
     string, or blank: 6 asks *)
  val s7d = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s7c, llam(change) => let
    val () = ended(change) in found_times(6) end)
  (* granted with no account, asked with a consent screen allowed *)
  val s8 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s7d, llam(change) => let
    val () = ended(change) in asked() end)
  (* canceled *)
  val s9 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s8, llam(change) => let
    val () = ended(change) in asked() end)
  (* another consent screen showing *)
  val s10 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s9, llam(change) => let
    val () = ended(change) in asked() end)
  (* an answer the plugin does not document: no authorization *)
  val s11 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s10, llam(change) => let
    val () = ended(change) in asked() end)
  (* Play services refused the consent: DEVELOPER_ERROR *)
  val s12 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s11, llam(change) => let
    val () = ended(change) in asked() end)
  (* Play services' own CANCELED: the reader backed out *)
  val s13 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s12, llam(change) => let
    val () = ended(change) in asked() end)
  (* a grant whose scopes are not a list: unexpected *)
  val s13b = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s13, llam(change) => let
    val () = ended(change) in asked() end)
  (* a token clear the platform refuses *)
  val s14 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s13b, llam(change) => let
    val () = ended(change) in clear_text("refused-token") end)
  (* a token clear that fails unexpectedly *)
  val s15 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s14, llam(change) => let
    val () = ended(change) in clear_text("odd-token") end)
  (* CONSENT_SHOWING for a clear, which shows no consent screen: unexpected *)
  val s16 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s15, llam(change) => let
    val () = ended(change) in clear_text("showing-token") end)
  (* a blank token is none: nothing asked *)
  val s17 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s16, llam(change) => let
    val () = ended(change) in clear_text("   ") end)
  (* revokes Play services refuses, answers unexpectedly, and answers
     with CONSENT_SHOWING, which it does not document *)
  val s18 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s17, llam(change) => let
    val () = ended(change) in revoke_text("refused@example.com") end)
  val s19 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s18, llam(change) => let
    val () = ended(change) in revoke_text("odd@example.com") end)
  val s20 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s19, llam(change) => let
    val () = ended(change) in revoke_text("showing@example.com") end)
in $P.finish<$GZ.google_authorization_change>(s20, llam(change) => ended(change)) end
