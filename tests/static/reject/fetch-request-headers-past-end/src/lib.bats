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

(* The header block's length must lie inside its buffer: 45 in a
   buffer of 44 does not *)
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
    headers_bytes, 45, body_bytes, 2)
  val () = release(method_frozen, method_bytes)
  val () = release(url_frozen, url_bytes)
  val () = release(headers_frozen, headers_bytes)
  val () = release(body_frozen, body_bytes)
in pending end
