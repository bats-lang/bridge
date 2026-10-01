#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

fn release {l:agz}{n:nat}
  (frozen: $A.frozenx(byte, l, n, 1, null), borrowed: $A.borrow(byte, l, n)): void = let
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

(* A header's length must lie inside its buffer: 2 in a buffer of 1
   does not *)
fn send (): $P.promise_pending(Int) = let
  val method = $A.alloc<byte>(3)
  val () = $A.write_text(method, 0, $A.text_lit("PUT"), 3)
  val url = $A.alloc<byte>(1)
  val () = $A.write_byte(url, 0, 47)
  val authorization = $A.alloc<byte>(5)
  val () = $A.write_text(authorization, 0, $A.text_lit("Basic"), 5)
  val match = $A.alloc<byte>(1)
  val body = $A.alloc<byte>(2)
  val () = $A.write_text(body, 0, $A.text_lit("{}"), 2)
  val @(method_frozen, method_bytes) = $A.freeze<byte>(method)
  val @(url_frozen, url_bytes) = $A.freeze<byte>(url)
  val @(authorization_frozen, authorization_bytes) = $A.freeze<byte>(authorization)
  val @(match_frozen, match_bytes) = $A.freeze<byte>(match)
  val @(body_frozen, body_bytes) = $A.freeze<byte>(body)
  val pending = $FE.fetch_send(method_bytes, 3, url_bytes, 1,
    authorization_bytes, 5, match_bytes, 2, body_bytes, 2)
  val () = release(method_frozen, method_bytes)
  val () = release(url_frozen, url_bytes)
  val () = release(authorization_frozen, authorization_bytes)
  val () = release(match_frozen, match_bytes)
  val () = release(body_frozen, body_bytes)
in pending end

