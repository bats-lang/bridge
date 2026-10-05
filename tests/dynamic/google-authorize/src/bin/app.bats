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
      val () = free_part(scopes)
    in free_part(account) end
  | ~$GZ.NotAuthorized() => ()
  | ~$GZ.AuthorizeCanceled() => ()
  | ~$GZ.AuthorizeFailed(code) => free_part(code)

implement $P.dispose<$GZ.google_authorization($GZ.Silently)>(answer) = free_authorization(answer)
implement $P.dispose<$GZ.google_authorization($GZ.MayAsk)>(answer) = free_authorization(answer)
implement $P.dispose<$GZ.google_authorization_change>(change) =
  case+ change of
  | ~$GZ.Changed() => ()
  | ~$GZ.ChangeFailed(code) => free_part(code)

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

vtypedef step = $P.promise($GZ.google_authorization_change, $P.Chained)

(* A step that does nothing more *)
fn done (): step = $P.ret<$GZ.google_authorization_change>($GZ.Changed())

(* How a clear or a revoke ended, in the hash *)
fn told_change (change: $GZ.google_authorization_change): step =
  case+ change of
  | ~$GZ.Changed() => let val () = hash_text("changed") in done() end
  | ~$GZ.ChangeFailed(code) => let val () = hash_code(code) in done() end

fn clear_bytes {l:agz}{n:pos} (a: $A.arr(byte, l, n), n: int n): step = let
  val @(frozen, borrowed) = $A.freeze<byte>(a)
  val cleared = $GZ.google_clear_token(borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(cleared, llam(change) => told_change(change)) end

(* Clears the token s *)
fn clear_text {n:pos | n < 256} (s: string n): step = let
  val () = hash_text("clear")
in clear_bytes(bytes(s), g1u2i(string1_length(s))) end

(* Revokes the account's grant of the scopes *)
fn revoke {la:agz}{na:pos}{ls:agz}{ns:pos}
  (account: $A.arr(byte, la, na), account_len: int na,
   scopes: $A.arr(byte, ls, ns), scopes_len: int ns): step = let
  val () = hash_text("revoke")
  val @(account_frozen, account_borrowed) = $A.freeze<byte>(account)
  val @(scopes_frozen, scopes_borrowed) = $A.freeze<byte>(scopes)
  val revoked = $GZ.google_revoke_access(account_borrowed, account_len, scopes_borrowed, scopes_len)
  val () = $A.drop<byte>(scopes_frozen, scopes_borrowed)
  val () = $A.free<byte>($A.thaw<byte>(scopes_frozen))
  val () = $A.drop<byte>(account_frozen, account_borrowed)
  val () = $A.free<byte>($A.thaw<byte>(account_frozen))
in $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(revoked, llam(change) => told_change(change)) end

(* An authorization given: "authorized" in the hash, then its token
   cleared and, when it names an account and its scopes, the account's
   grant of them revoked, so the plugin prints what came back *)
fn told_authorized {k:pos}
  (token: $BD.dblob(k), scopes: $R.option([n:pos] $BD.dblob(n)), account: $R.option([n:pos] $BD.dblob(n))): step = let
  val () = hash_text("authorized")
  val @(token_bytes, token_len) = copied(token)
  val cleared = clear_bytes(token_bytes, token_len)
in
  case+ account of
  | ~$R.none() => let
      val () = free_part(scopes)
      val () = hash_text("no account")
    in cleared end
  | ~$R.some(account) => (case+ scopes of
    | ~$R.none() => let
        val () = $BD.blob_free(account)
        val () = hash_text("no scopes")
      in cleared end
    | ~$R.some(scopes) => let
        val @(account_bytes, account_len) = copied(account)
        val @(scopes_bytes, scopes_len) = copied(scopes)
      in $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(cleared, llam(_) =>
        revoke(account_bytes, account_len, scopes_bytes, scopes_len)) end)
end

fn told_found (answer: $GZ.google_authorization($GZ.Silently)): step =
  case+ answer of
  | ~$GZ.Authorized(token, scopes, account) => told_authorized(token, scopes, account)
  | ~$GZ.NotAuthorized() => let val () = hash_text("not authorized") in done() end
  | ~$GZ.AuthorizeFailed(code) => let val () = hash_code(code) in done() end

fn told_asked (answer: $GZ.google_authorization($GZ.MayAsk)): step =
  case+ answer of
  | ~$GZ.Authorized(token, scopes, account) => told_authorized(token, scopes, account)
  | ~$GZ.AuthorizeCanceled() => let val () = hash_text("canceled") in done() end
  | ~$GZ.AuthorizeFailed(code) => let val () = hash_code(code) in done() end

(* Asks for scopes s with no UI *)
fn found {n:pos | n < 256} (s: string n): step = let
  val () = hash_text("authorization for scopes")
  val @(frozen, borrowed) = $A.freeze<byte>(bytes(s))
  val asked = $GZ.google_authorization_for_scopes(borrowed, g1u2i(string1_length(s)))
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in $P.and_then<$GZ.google_authorization($GZ.Silently)><$GZ.google_authorization_change>(asked, llam(answer) => told_found(answer)) end

(* Asks for scopes s, a consent screen allowed *)
fn asked {n:pos | n < 256} (s: string n): step = let
  val () = hash_text("authorize scopes")
  val @(frozen, borrowed) = $A.freeze<byte>(bytes(s))
  val asked = $GZ.google_authorize_scopes(borrowed, g1u2i(string1_length(s)))
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in $P.and_then<$GZ.google_authorization($GZ.MayAsk)><$GZ.google_authorization_change>(asked, llam(answer) => told_asked(answer)) end

(* A step's end, read: nothing to do with it but let it go *)
fn ended (change: $GZ.google_authorization_change): void =
  case+ change of
  | ~$GZ.Changed() => ()
  | ~$GZ.ChangeFailed(code) => free_part(code)

(* check.mjs plays the native app with the GoogleAuthorize plugin, whose
   answers come in the order of the calls below, and a browser (no
   Capacitor). Each call is named in the hash, then its answer; an authorization's token
   is cleared and its account's grant of its scopes revoked, so the
   plugin prints them as they came back *)
implement main0 () = let
  val () = (if $GZ.google_authorize_available() then hash_text("available") else hash_text("unavailable"))
  (* granted, with an account *)
  val s1 = found("scope-a scope-b")
  (* consent needed *)
  val s2 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s1, llam(change) => let
    val () = ended(change) in found("scope-a") end)
  (* the platform refused, with its code *)
  val s3 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s2, llam(change) => let
    val () = ended(change) in found("scope-a") end)
  (* refused with no code *)
  val s4 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s3, llam(change) => let
    val () = ended(change) in found("scope-a") end)
  (* granted with no account, asked with a consent screen allowed *)
  val s5 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s4, llam(change) => let
    val () = ended(change) in asked("scope-a  scope-c") end)
  (* canceled *)
  val s6 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s5, llam(change) => let
    val () = ended(change) in asked("scope-a") end)
  (* another consent screen showing *)
  val s7 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s6, llam(change) => let
    val () = ended(change) in asked("scope-a") end)
  (* an answer the plugin does not document: no authorization *)
  val s8 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s7, llam(change) => let
    val () = ended(change) in asked("scope-a") end)
  (* a token clear the platform refuses *)
  val s9 = $P.and_then<$GZ.google_authorization_change><$GZ.google_authorization_change>(s8, llam(change) => let
    val () = ended(change) in clear_text("refused-token") end)
in $P.finish<$GZ.google_authorization_change>(s9, llam(change) => ended(change)) end
