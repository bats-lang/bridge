#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.bats"
staload WI = "wasm.bats-packages.dev/bridge/src/window.bats"

(* s's bytes in a fresh array of exactly its length; "" is one byte *)
fn bytes {n:nat | n < 256} (s: string n): [l:agz][m:pos | m >= n] $A.arr(byte, l, m) = let
  val n = g1u2i(string1_length(s))
  val size = (if n > 0 then n else 1): [m:pos | m >= n; m < 256] int m
  val a = $A.alloc<byte>(size)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

(* s's bytes in a fresh array of exactly its length *)
fn exact {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

(* Logs a line at info *)
fn say {n:pos | n < 256} (line: string n): void = let
  val n = g1u2i(string1_length(line))
  val text = $A.alloc<byte>(n)
  val () = $A.write_text(text, 0, $A.text_lit(line), n)
  val @(frozen, borrowed) = $A.freeze<byte>(text)
  val () = $WI.log($WI.Info(), borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

(* Whether the response has an ETag header (its value read into 16
   bytes) *)
fn tagged (r: !$FE.response): bool = let
  val @(name_frozen, name) = $A.freeze<byte>(exact("ETag"))
  val out = $A.alloc<byte>(16)
  val found = $FE.fetch_header(r, name, 4, out, 16)
  val () = $A.free<byte>(out)
  val () = $A.drop<byte>(name_frozen, name)
  val () = $A.free<byte>($A.thaw<byte>(name_frozen))
in case+ found of ~$R.some(_) => true | ~$R.none() => false end

(* Sends method url with these headers' values and body; logs whether a
   response came back, and whether it has an ETag *)
fn send {nm,nu:pos | nm < 256; nu < 256}{na,nt,nb:nat | na < 256; nt < 256; nb < 256}{ns,ng,nf:pos | ns < 256; ng < 256; nf < 256}
  (method: string nm, url: string nu, authorization: string na, match: string nt, body: string nb,
   sent: string ns, sent_tagged: string ng, failed: string nf): void = let
  val @(method_frozen, method_bytes) = $A.freeze<byte>(exact(method))
  val @(url_frozen, url_bytes) = $A.freeze<byte>(exact(url))
  val @(authorization_frozen, authorization_bytes) = $A.freeze<byte>(bytes(authorization))
  val @(match_frozen, match_bytes) = $A.freeze<byte>(bytes(match))
  val @(body_frozen, body_bytes) = $A.freeze<byte>(bytes(body))
  val asked = $FE.fetch_send(method_bytes, g1u2i(string1_length(method)), url_bytes, g1u2i(string1_length(url)),
    authorization_bytes, g1u2i(string1_length(authorization)), match_bytes, g1u2i(string1_length(match)),
    body_bytes, g1u2i(string1_length(body)))
  val () = $A.drop<byte>(body_frozen, body_bytes)
  val () = $A.free<byte>($A.thaw<byte>(body_frozen))
  val () = $A.drop<byte>(match_frozen, match_bytes)
  val () = $A.free<byte>($A.thaw<byte>(match_frozen))
  val () = $A.drop<byte>(authorization_frozen, authorization_bytes)
  val () = $A.free<byte>($A.thaw<byte>(authorization_frozen))
  val () = $A.drop<byte>(url_frozen, url_bytes)
  val () = $A.free<byte>($A.thaw<byte>(url_frozen))
  val () = $A.drop<byte>(method_frozen, method_bytes)
  val () = $A.free<byte>($A.thaw<byte>(method_frozen))
in $P.finish<$FE.fetched>(asked, llam (got) =>
  case+ got of
  | ~$FE.Responded(r) => let
      val with_tag = tagged(r)
      val () = $DC.blob_free($FE.fetch_body(r))
    in if with_tag then say(sent_tagged) else say(sent) end
  | ~$FE.NoResponse() => say(failed)) end

(* A PUT with both headers (answered with an ETag), a GET with neither
   (answered with an empty one), a DELETE with only If-Match (answered
   with none), and a request whose Authorization holds a line break (not
   made) *)
implement main0 () = let
  val () = send("PUT", "/a", "Basic dXNlcjpwYXNz", "\"e1\"", "body", "1 sent", "1 sent, tagged", "1 failed")
  val () = send("GET", "/b", "", "", "", "2 sent", "2 sent, tagged", "2 failed")
  val () = send("DELETE", "/c", "", "\"e2\"", "", "3 sent", "3 sent, tagged", "3 failed")
in send("GET", "/d", "Basic a\nX-Injected: yes", "", "", "4 sent", "4 sent, tagged", "4 failed") end
