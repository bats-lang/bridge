#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.sats"

fn release {l:agz}{n:nat}
  (frozen: $A.frozenx(byte, l, n, 1, null), borrowed: $A.borrow(byte, l, n)): void = let
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

(* A POST with a body and two header lines, "Dropbox-API-Arg: {}" and
   "Content-Type: text/plain", separated by a newline (byte 10) *)
fn send (): $P.promise_pending(Int) = let
  val method = $A.alloc<byte>(4)
  val () = $A.write_text(method, 0, $A.text_lit("POST"), 4)
  val url = $A.alloc<byte>(1)
  val () = $A.write_byte(url, 0, 47)
  val headers = $A.alloc<byte>(44)
  val () = $A.write_text(headers, 0, $A.text_lit("Dropbox-API-Arg: {}"), 19)
  val () = $A.write_byte(headers, 19, 10)
  val () = $A.write_text(headers, 20, $A.text_lit("Content-Type: text/plain"), 24)
  val body = $A.alloc<byte>(2)
  val () = $A.write_text(body, 0, $A.text_lit("hi"), 2)
  val @(method_frozen, method_bytes) = $A.freeze<byte>(method)
  val @(url_frozen, url_bytes) = $A.freeze<byte>(url)
  val @(headers_frozen, headers_bytes) = $A.freeze<byte>(headers)
  val @(body_frozen, body_bytes) = $A.freeze<byte>(body)
  val pending = $FE.fetch_request(method_bytes, 4, url_bytes, 1,
    headers_bytes, 44, body_bytes, 2)
  val () = release(method_frozen, method_bytes)
  val () = release(url_frozen, url_bytes)
  val () = release(headers_frozen, headers_bytes)
  val () = release(body_frozen, body_bytes)
in pending end

(* The response's Dropbox-API-Result header read into 64 bytes: its
   length is inside the buffer, so a read of its last byte is too *)
fn result_last {l:agz} (h: Int, out: !$A.arr(byte, l, 64)): int = let
  val name = $A.alloc<byte>(18)
  val () = $A.write_text(name, 0, $A.text_lit("Dropbox-API-Result"), 18)
  val @(name_frozen, name_bytes) = $A.freeze<byte>(name)
  val len = $FE.fetch_header(h, name_bytes, 18, out, 64)
  val () = release(name_frozen, name_bytes)
in if len > 0 then byte2int0($A.get<byte>(out, len - 1)) else 0 end

fn result (h: Int): int = let
  val out = $A.alloc<byte>(64)
  val last = result_last(h, out)
  val () = $A.free<byte>(out)
in last end
