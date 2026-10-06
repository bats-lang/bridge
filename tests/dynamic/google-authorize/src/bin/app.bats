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
  | ~$GZ.AuthorizeCanceled(message) => free_part(message)
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
   ASCII character, are not well-formed UTF-8, start with a byte order
   mark, or are too long to be one *)
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

(* An authorization given: "authorized" and the scopes granted in the
   hash, then its token cleared and, when it names an account, that
   account's grant of drive.appdata revoked (else "no account" in the
   hash), so the plugin prints the token and the account as they came
   back *)
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
  | ~$GZ.AuthorizeCanceled(message) => let
      val () = hash_text("canceled")
      val () = hash_message(message)
    in done() end
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
fn scope_case {l:agz}{at:nat | at < 17}{n:pos | n < 256} (out: !$A.arr(byte, l, 17), at: int at, text: string n): void =
  case+ $GZ.google_scope_of(text) of
  | ~$R.some(_) => $A.set<byte>(out, at, int2byte0(121))
  | ~$R.none() => $A.set<byte>(out, at, int2byte0(110))

(* Only a scope-token is a scope: no whitespace of any kind, no other
   control character, no quote or backslash, nothing non-ASCII. One
   hash, seventeen letters alone, a y or n for each of: a space, a tab, a
   line feed, a carriage return, a form feed, a vertical tab, an
   ideographic space, a quote, a backslash, a control character that is
   not whitespace (0x01), DEL (0x7F) (each n); then each end of NQCHAR's
   ranges, 0x21, 0x23, 0x5B, 0x5D and 0x7E, and drive.appdata's scope
   (each y) *)
fn split_scope (): void = let
  val out = $A.alloc<byte>(17)
  val () = scope_case(out, 0, "scope-a scope-b")
  val () = scope_case(out, 1, "scope-a\tscope-b")
  val () = scope_case(out, 2, "scope-a\nscope-b")
  val () = scope_case(out, 3, "scope-a\rscope-b")
  val () = scope_case(out, 4, "scope-a\014scope-b")
  val () = scope_case(out, 5, "\013")
  val () = scope_case(out, 6, "\343\200\200")
  val () = scope_case(out, 7, "scope\"a")
  val () = scope_case(out, 8, "scope\\a")
  val () = scope_case(out, 9, "scope\001a")
  val () = scope_case(out, 10, "scope\177a")
  val () = scope_case(out, 11, "!")
  val () = scope_case(out, 12, "#")
  val () = scope_case(out, 13, "[")
  val () = scope_case(out, 14, "]")
  val () = scope_case(out, 15, "~")
  val () = scope_case(out, 16, "https://www.googleapis.com/auth/drive.appdata")
in hash_bytes(out, 17) end

(* Whether bytes are a google_text: y or n at out[at] *)
fn text_case {l:agz}{at:nat | at < 51}{n:pos | n < 256} (out: !$A.arr(byte, l, 51), at: int at, text: string n): void =
  case+ text_of(bytes(text), g1u2i(string1_length(text))) of
  | ~$R.some(made) => let
      val () = $GZ.google_text_free(made)
    in $A.set<byte>(out, at, int2byte0(121)) end
  | ~$R.none() => $A.set<byte>(out, at, int2byte0(110))

(* Only well-formed UTF-8 with no leading byte order mark, holding a
   visible ASCII character, is a google_text. One hash, fifty-one
   letters alone, a y or n for each of: an a then a lone continuation
   byte (0x80), the overlong forms C0 AF, E0 9F BF and F0 8F BF BF, a
   surrogate (ED A0 80), a code point over U+10FFFF (F4 90 80 80), F5
   80 80 80, and a sequence cut short (E2 82) (each n); an a then a character of
   two bytes (C3 A9), three (E4 B8 AD), four (F0 9F 98 80) and the
   last code point (F4 8F BF BF), an exclamation mark (0x21) alone and
   a tilde (0x7E) alone (each y); DEL (0x7F) alone, a space alone, a
   byte order mark then abc, and a, 0xFF, b (each n); an a then C3 cut
   short, C3 7F, E4 B8 7F, F0 9F 98 cut short, F0 9F 7F 80, F0 9F 98
   7F, and C1 BF (each n); an a then the lowest of each form, C2 80,
   E0 A0 80 and F0 90 80 80, and the highest below the surrogates, ED
   9F BF; EF BB 80 (U+FEC0) then a; and an a then a byte order mark,
   which does not lead (each y); EF BC BF (U+FF3F) then a (y); an a
   then a continuation above BF in each place, C3 C0, E4 C0 80, E4 B8
   C0, F0 9F C0 80, F0 9F 98 C0 and F1 C0 80 80, and then a second
   byte below 80 after E4, F1 and F4, E4 7F 80, F1 7F 80 80 and F4 7F
   80 80 (each n); an a then F1 80 80 80, DF BF, DEL, E1 80 80, EF BF
   BD and F0 BF BF BF (each y); EE BB BF then a, F0 BB BF 80 then a,
   EF BA BF then a, and EF BB BE then a (each y). Each value bound of
   _visible and _utf8 and each byte _byte_order_mark compares with,
   moved by one either way, and each of their checks, left out,
   changes a letter. The length guards (at + 1, + 2 and + 3 below n,
   and n below 3) are held by the types, which refuse an index not
   below n; _byte_order_mark's n below 3 moved up to 4 cannot be seen,
   as the only text it would let through, EF BB BF alone, holds no
   visible ASCII character *)
fn text_row (): void = let
  val out = $A.alloc<byte>(51)
  val () = text_case(out, 0, "a\200")
  val () = text_case(out, 1, "a\300\257")
  val () = text_case(out, 2, "a\340\237\277")
  val () = text_case(out, 3, "a\360\217\277\277")
  val () = text_case(out, 4, "a\355\240\200")
  val () = text_case(out, 5, "a\364\220\200\200")
  val () = text_case(out, 6, "a\365\200\200\200")
  val () = text_case(out, 7, "a\342\202")
  val () = text_case(out, 8, "a\303\251")
  val () = text_case(out, 9, "a\344\270\255")
  val () = text_case(out, 10, "a\360\237\230\200")
  val () = text_case(out, 11, "a\364\217\277\277")
  val () = text_case(out, 12, "!")
  val () = text_case(out, 13, "~")
  val () = text_case(out, 14, "\177")
  val () = text_case(out, 15, " ")
  val () = text_case(out, 16, "\357\273\277abc")
  val () = text_case(out, 17, "a\377b")
  val () = text_case(out, 18, "a\303")
  val () = text_case(out, 19, "a\303\177")
  val () = text_case(out, 20, "a\344\270\177")
  val () = text_case(out, 21, "a\360\237\230")
  val () = text_case(out, 22, "a\360\237\177\200")
  val () = text_case(out, 23, "a\360\237\230\177")
  val () = text_case(out, 24, "a\301\277")
  val () = text_case(out, 25, "a\302\200")
  val () = text_case(out, 26, "a\340\240\200")
  val () = text_case(out, 27, "a\360\220\200\200")
  val () = text_case(out, 28, "a\355\237\277")
  val () = text_case(out, 29, "\357\273\200a")
  val () = text_case(out, 30, "a\357\273\277")
  val () = text_case(out, 31, "\357\274\277a")
  val () = text_case(out, 32, "a\303\300")
  val () = text_case(out, 33, "a\344\300\200")
  val () = text_case(out, 34, "a\344\270\300")
  val () = text_case(out, 35, "a\360\237\300\200")
  val () = text_case(out, 36, "a\360\237\230\300")
  val () = text_case(out, 37, "a\361\300\200\200")
  val () = text_case(out, 38, "a\344\177\200")
  val () = text_case(out, 39, "a\361\177\200\200")
  val () = text_case(out, 40, "a\364\177\200\200")
  val () = text_case(out, 41, "a\361\200\200\200")
  val () = text_case(out, 42, "a\337\277")
  val () = text_case(out, 43, "a\177")
  val () = text_case(out, 44, "a\341\200\200")
  val () = text_case(out, 45, "a\357\277\275")
  val () = text_case(out, 46, "a\360\277\277\277")
  val () = text_case(out, 47, "\356\273\277a")
  val () = text_case(out, 48, "\360\273\277\200a")
  val () = text_case(out, 49, "\357\272\277a")
  val () = text_case(out, 50, "\357\273\276a")
in hash_bytes(out, 51) end

(* A step's end, read: nothing to do with it but let it go *)
fn ended (change: $GZ.google_authorization_change): void =
  case+ change of
  | ~$GZ.Changed() => ()
  | ~$GZ.ChangeRefused(_, message) => free_part(message)
  | ~$GZ.ChangeUnavailable() => ()
  | ~$GZ.ChangeUnexpected(code, message) => let val () = free_part(code) in free_part(message) end

(* Asks for drive.appdata with no UI left times, one after another *)
fun found_times {left:pos} .<left>. (left: int left): step =
  if left <= 1 then found()
  else $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(found(), llam(change) => let
    val () = ended(change) in found_times(left - 1) end)

(* check.mjs plays the native app with the GoogleAuthorize plugin, whose
   answers come in the order of the calls below, and a browser (no
   Capacitor). Each call is named in the hash, then its answer; an
   authorization's token is cleared and, when it names an account, that
   account's grant of drive.appdata revoked, so the plugin prints the
   token and the account as they came back *)
implement main0 () = let
  val () = (if $GZ.google_authorize_available() then hash_text("available") else hash_text("unavailable"))
  (* what is not a scope-token is refused as it is made *)
  val () = split_scope()
  (* what is not a token or an account is refused as it is made *)
  val () = text_row()
  (* drive.appdata asked twice (two scopes); granted, with an account *)
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
  (* the 14 statuses CommonStatusCodes names but NETWORK_ERROR and
     CANCELED (asked above), INTERNAL_ERROR (driven through a clear) and
     DEVELOPER_ERROR (through authorizeScopes), then SUCCESS, which is no
     refusal: 15 asks *)
  val s7c = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s7b, llam(change) => let
    val () = ended(change) in found_times(15) end)
  (* in check.mjs's order, answers authorizationForScopes does not
     document (D) and grants the plugin passes on that bridge does not
     take (G): no authorization (D), a null answer (D), a blank token
     (D), no scope granted (D), an account that is empty, not a string,
     or blank (D), a granted scope holding a space (G), one that is not
     a string (D), a blank one and an empty one (D), one holding a quote, a backslash, a letter outside
     ASCII, a control character (0x01) or DEL (G: none a scope-token),
     no access token (D), one that is not a string (D), a token and an
     account holding no visible ASCII character (G), an answer with no
     account key (D), a token and an account over 4096 bytes (G), and a
     token and an account holding a lone surrogate (G: not well-formed
     Unicode);
     then a status with an empty message (no message kept); then a
     rejection with no value, a string, an error whose code is a number,
     one whose message is a number, null, and one whose message holds a
     lone surrogate, each said to be no error whose code and message
     are text (D), an object with no code and no message (none and
     none), an error whose code is null (unexpected, no code, its
     message) and one whose message is null (refused, no message);
     then an authorization that is not an
     object (D), a token and an account starting with a byte order mark
     (G), a token of exactly 4096 bytes (taken and cleared), one of 4097
     bytes in 2049 UTF-16 units (G), an account of exactly 4096 bytes
     (taken, the token cleared and its grant revoked), one of 4097 bytes
     (G), an account holding a letter outside ASCII (taken and revoked
     as it came), and a scope holding each end of NQCHAR's ranges
     (taken); then a token of each end of googleBlank's ranges (D: empty
     or blank), one of each of sixteen characters just outside them (G:
     no visible ASCII character), a token of only an exclamation mark
     and an account of only a tilde (taken, cleared and revoked), a
     token holding a surrogate pair and a byte order mark that does not
     lead (taken and cleared), a token of only DEL and one of a space
     and a letter outside ASCII (G: no visible ASCII character), and
     granted scopes with a hole (D): 66 asks *)
  val s7d = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s7c, llam(change) => let
    val () = ended(change) in found_times(66) end)
  (* granted with no account, asked with a consent screen allowed *)
  val s8 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s7d, llam(change) => let
    val () = ended(change) in asked() end)
  (* the plugin's CANCELED: the reader backed out, its message kept *)
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
  (* Play services' own CANCELED status (16): AuthorizeCanceled too, its
     message kept (bats-lang/capacitor-plugins#8) *)
  val s13 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s12, llam(change) => let
    val () = ended(change) in asked() end)
  (* a grant whose scopes are not a list: unexpected *)
  val s13b = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s13, llam(change) => let
    val () = ended(change) in asked() end)
  (* the plugin's UNEXPECTED, a rejection with no code, a code nothing
     documents, each from authorizeScopes *)
  val s13c = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s13b, llam(change) => let
    val () = ended(change) in asked() end)
  val s13d = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s13c, llam(change) => let
    val () = ended(change) in asked() end)
  val s13e = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s13d, llam(change) => let
    val () = ended(change) in asked() end)
  (* a token clear the platform refuses *)
  val s14 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s13e, llam(change) => let
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
  (* a clear refused with an empty message (no message kept), and a
     revoke rejected with no value (said to be no error) *)
  val s21 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s20, llam(change) => let
    val () = ended(change) in clear_text("quiet-token") end)
  val s22 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s21, llam(change) => let
    val () = ended(change) in revoke_text("silent@example.com") end)
  (* a clear rejected with a string, not an error: unexpected, said so *)
  val s23 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s22, llam(change) => let
    val () = ended(change) in clear_text("string-token") end)
  (* a token whose bytes are not well-formed UTF-8 (0xFF) is none:
     nothing asked *)
  val s24 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s23, llam(change) => let
    val () = ended(change) in clear_text("a\377b") end)
  (* a clear rejected with an error whose message is a number, and a
     revoke rejected with null: each said to be no error *)
  val s25 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s24, llam(change) => let
    val () = ended(change) in clear_text("number-token") end)
  val s26 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s25, llam(change) => let
    val () = ended(change) in revoke_text("null@example.com") end)
  (* a clear rejected with an error whose code holds a lone surrogate:
     said to be no error whose code and message are text *)
  val s27 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s26, llam(change) => let
    val () = ended(change) in clear_text("surrogate-token") end)
in $P.finish<$GZ.google_authorization_change>(s27, llam(change) => ended(change)) end
