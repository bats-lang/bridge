#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload GA = "wasm.bats-packages.dev/bridge/src/google_account.bats"
staload BF = "wasm.bats-packages.dev/bridge/src/backup_file.bats"

(* Answers nobody took, freed: before their first use *)
implement $P.dispose<$BF.backup_written>(_) = ()
implement $P.dispose<$BF.backup_found>(found) =
  case+ found of
  | ~$BF.BackupFound(blob) => $BD.blob_free(blob)
  | ~$BF.BackupNone() => ()
  | ~$BF.BackupUnreadable() => ()
implement $P.dispose<$GA.google_token>(answer) =
  case+ answer of
  | ~$GA.GoogleToken(token, account) => let
      val () = $BD.blob_free(token)
    in case+ account of ~$R.some(a) => $BD.blob_free(a) | ~$R.none() => () end
  | ~$GA.GoogleNoAccount() => ()
  | ~$GA.GoogleCanceled() => ()
  | ~$GA.GoogleRefused() => ()
  | ~$GA.GoogleUnavailable() => ()
implement $P.dispose<$GA.google_signed_out>(_) = ()

(* s's bytes in a fresh array of exactly its length *)
fn bytes {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

(* Writes the text as the backed-up file name *)
fn write_text {n:pos | n < 256}{t:pos | t < 256} (name: string n, text: string t): $P.promise($BF.backup_written, $P.Chained) = let
  val @(name_frozen, name_bytes) = $A.freeze<byte>(bytes(name))
  val @(text_frozen, text_bytes) = $A.freeze<byte>(bytes(text))
  val written = $BF.backup_file_write(name_bytes, g1u2i(string1_length(name)), text_bytes, g1u2i(string1_length(text)))
  val () = $A.drop<byte>(text_frozen, text_bytes)
  val () = $A.free<byte>($A.thaw<byte>(text_frozen))
  val () = $A.drop<byte>(name_frozen, name_bytes)
  val () = $A.free<byte>($A.thaw<byte>(name_frozen))
in written end

(* The blob's bytes, k of them, written as the backed-up file name *)
fn write_copy {n:pos | n < 256}{k:pos | k <= 4096} (name: string n, blob: $BD.dblob(k), k: int k): $P.promise($BF.backup_written, $P.Chained) = let
  val copy = $A.alloc<byte>(k)
  val () = $BD.blob_read(blob, 0, copy, k)
  val () = $BD.blob_free(blob)
  val @(name_frozen, name_bytes) = $A.freeze<byte>(bytes(name))
  val @(copy_frozen, copy_bytes) = $A.freeze<byte>(copy)
  val written = $BF.backup_file_write(name_bytes, g1u2i(string1_length(name)), copy_bytes, k)
  val () = $A.drop<byte>(copy_frozen, copy_bytes)
  val () = $A.free<byte>($A.thaw<byte>(copy_frozen))
  val () = $A.drop<byte>(name_frozen, name_bytes)
  val () = $A.free<byte>($A.thaw<byte>(name_frozen))
in written end

(* Writes the blob's bytes as the backed-up file name, and frees it *)
fn write_blob {n:pos | n < 256}{k:pos} (name: string n, blob: $BD.dblob(k)): $P.promise($BF.backup_written, $P.Chained) = let
  val k = $BD.blob_len(blob)
in
  if k > 4096 then let
    val () = $BD.blob_free(blob)
  in write_text(name, "too long") end
  else write_copy(name, blob, k)
end

(* Reads the backed-up file name *)
fn read {n:pos | n < 256} (name: string n): $P.promise($BF.backup_found, $P.Chained) = let
  val @(name_frozen, name_bytes) = $A.freeze<byte>(bytes(name))
  val found = $BF.backup_file_read(name_bytes, g1u2i(string1_length(name)))
  val () = $A.drop<byte>(name_frozen, name_bytes)
  val () = $A.free<byte>($A.thaw<byte>(name_frozen))
in found end

(* What a token asked for came to, as the backed-up files check.mjs
   prints: the token, and the account's address *)
fn token_written (answer: $GA.google_token): $P.promise($BF.backup_written, $P.Chained) =
  case+ answer of
  | ~$GA.GoogleToken(token, account) => let
      val () = (case+ account of
        | ~$R.some(address) => $P.finish<$BF.backup_written>(write_blob("account", address), llam(_) => ())
        | ~$R.none() => $P.finish<$BF.backup_written>(write_text("account", "none"), llam(_) => ()))
    in write_blob("token", token) end
  | ~$GA.GoogleNoAccount() => write_text("token", "no account")
  | ~$GA.GoogleCanceled() => write_text("token", "canceled")
  | ~$GA.GoogleRefused() => write_text("token", "refused")
  | ~$GA.GoogleUnavailable() => write_text("token", "unavailable")

(* What a read found, written again as the backed-up file name *)
fn found_written {n:pos | n < 256} (name: string n, found: $BF.backup_found): $P.promise($BF.backup_written, $P.Chained) =
  case+ found of
  | ~$BF.BackupFound(blob) => write_blob(name, blob)
  | ~$BF.BackupNone() => write_text(name, "none")
  | ~$BF.BackupUnreadable() => write_text(name, "unreadable")

(* check.mjs plays the app's GoogleSignIn and Filesystem: a token is
   asked for and written as a backed-up file, read back and written
   again, a file never written is read, a second token is refused (no
   account), and the account is signed out *)
implement main0 () =
  if ~$GA.google_token_available() then $P.finish<$BF.backup_written>(write_text("token", "unavailable"), llam(_) => ())
  else if ~$BF.backup_file_available() then ()
  else let
    val @(client_frozen, client) = $A.freeze<byte>(bytes("client-id"))
    val @(scope_frozen, scope) = $A.freeze<byte>(bytes("scope"))
    val asked = $GA.google_token_get(client, 9, scope, 5)
    val () = $A.drop<byte>(scope_frozen, scope)
    val () = $A.free<byte>($A.thaw<byte>(scope_frozen))
    val () = $A.drop<byte>(client_frozen, client)
    val () = $A.free<byte>($A.thaw<byte>(client_frozen))
    val written = $P.and_then<$GA.google_token><$BF.backup_written>(asked, llam(answer) => token_written(answer))
    val again = $P.and_then<$BF.backup_written><$BF.backup_found>(written, llam(_) => read("token"))
    val copied = $P.and_then<$BF.backup_found><$BF.backup_written>(again, llam(found) => found_written("again", found))
    val missing = $P.and_then<$BF.backup_written><$BF.backup_found>(copied, llam(_) => read("missing"))
    val noted = $P.and_then<$BF.backup_found><$BF.backup_written>(missing, llam(found) => found_written("missing", found))
    val second = $P.and_then<$BF.backup_written><$GA.google_token>(noted, llam(_) => let
      val @(client_frozen, client) = $A.freeze<byte>(bytes("client-id"))
      val @(scope_frozen, scope) = $A.freeze<byte>(bytes("scope"))
      val asked = $GA.google_token_get(client, 9, scope, 5)
      val () = $A.drop<byte>(scope_frozen, scope)
      val () = $A.free<byte>($A.thaw<byte>(scope_frozen))
      val () = $A.drop<byte>(client_frozen, client)
      val () = $A.free<byte>($A.thaw<byte>(client_frozen))
    in asked end)
    val refused = $P.and_then<$GA.google_token><$BF.backup_written>(second, llam(answer) => token_written(answer))
    val out = $P.and_then<$BF.backup_written><$GA.google_signed_out>(refused, llam(_) => $GA.google_sign_out())
  in $P.finish<$GA.google_signed_out>(out, llam(_) => ()) end
