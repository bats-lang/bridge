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

(* A PUT with a body, an Authorization header and no If-Match (its
   length 0 inside a buffer of 1) *)
fn send (): $P.promise($FE.fetched, $P.Chained) = let
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
    authorization_bytes, 5, match_bytes, 0, body_bytes, 2)
  val () = release(method_frozen, method_bytes)
  val () = release(url_frozen, url_bytes)
  val () = release(authorization_frozen, authorization_bytes)
  val () = release(match_frozen, match_bytes)
  val () = release(body_frozen, body_bytes)
in pending end

(* The last byte of a tag of etag_len bytes in a buffer of etag_size *)
fn last {l:agz}{etag_size:pos}{etag_len:nat | etag_len <= etag_size}
  (etag: !$A.arr(byte, l, etag_size), etag_len: int etag_len): int =
  if etag_len > 0 then byte2int0($A.get<byte>(etag, etag_len - 1)) else 0

(* The response's ETag, then its body let go: the tag's length is
   inside the buffer, so a read of it is too *)
fn take {l:agz} (got: $FE.fetched, etag: !$A.arr(byte, l, 64)): int =
  case+ got of
  | ~$FE.NoResponse() => 0
  | ~$FE.Responded(r) => let
      val name = $A.alloc<byte>(4)
      val () = $A.write_text(name, 0, $A.text_lit("ETag"), 4)
      val @(name_frozen, name_bytes) = $A.freeze<byte>(name)
      val found = $FE.fetch_header(r, name_bytes, 4, etag, 64)
      val () = release(name_frozen, name_bytes)
      val () = $BD.blob_free($FE.fetch_body(r))
    in
      case+ found of
      | ~$R.some(etag_len) => last(etag, etag_len)
      | ~$R.none() => 0
    end

fn claim (got: $FE.fetched): int = let
  val etag = $A.alloc<byte>(64)
  val result = take(got, etag)
  val () = $A.free<byte>(etag)
in result end
