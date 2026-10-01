(* fetch -- network fetch with promise-based async for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"
(* file.bats does not staload this file, so this is no cycle *)
staload "./file.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* Fetches the URL; the promise resolves with a handle to the response,
   0 when the request failed, to claim with fetch_claim (or
   fetch_claim_file) *)
#pub fun fetch
  : {lb:agz}{n:pos}
  (!$A.borrow(byte, lb, n), int n) -> $P.promise_pending(Int)

(* The response a fetch promise resolved with: its HTTP status and its
   body, a blob of its own size; none when the request failed or the
   handle is not a pending response. Claimed once. *)
#pub fun fetch_claim
  (handle: Int): $R.option(@([s:int] int s, [k:nat] dblob(k)))

(* Sends a request: its method (GET, PUT and the like), the URL, the
   value of its Authorization header and of its If-Match header (each
   left out when it is empty) and its body (none when it is empty).
   The promise resolves as fetch's does, with a handle to claim with
   fetch_claim or fetch_claim_tagged *)
#pub fun fetch_send
  : {method_loc:agz}{method_len:pos}{url_loc:agz}{url_len:pos}
    {authorization_loc:agz}{authorization_size:nat}{authorization_len:nat | authorization_len <= authorization_size}
    {match_loc:agz}{match_size:nat}{match_len:nat | match_len <= match_size}
    {body_loc:agz}{body_size:nat}{body_len:nat | body_len <= body_size}
  (!$A.borrow(byte, method_loc, method_len), int method_len,
   !$A.borrow(byte, url_loc, url_len), int url_len,
   !$A.borrow(byte, authorization_loc, authorization_size), int authorization_len,
   !$A.borrow(byte, match_loc, match_size), int match_len,
   !$A.borrow(byte, body_loc, body_size), int body_len) -> $P.promise_pending(Int)

(* Sends a request: its method, the URL, its headers as a block of
   "Name: value" lines separated by newlines (any number; an empty line
   or one with no name is skipped, and each name and value is trimmed)
   and its body (none when it is empty). The headers and the body may
   be empty: length 0 inside a buffer. The promise resolves as fetch's
   does, with a handle to claim with fetch_claim or fetch_claim_tagged,
   and 0 when the request failed, even at once (a header the browser
   refuses). The response is not cached. *)
#pub fun fetch_request
  : {method_loc:agz}{method_len:pos}{url_loc:agz}{url_len:pos}
    {headers_loc:agz}{headers_size:nat}{headers_len:nat | headers_len <= headers_size}
    {body_loc:agz}{body_size:nat}{body_len:nat | body_len <= body_size}
  (!$A.borrow(byte, method_loc, method_len), int method_len,
   !$A.borrow(byte, url_loc, url_len), int url_len,
   !$A.borrow(byte, headers_loc, headers_size), int headers_len,
   !$A.borrow(byte, body_loc, body_size), int body_len) -> $P.promise_pending(Int)

(* The named header of a pending response (one a fetch promise resolved
   with, not yet claimed) written to out: its length, at most out_size,
   and 0 when the response has no such header, it is longer, or the
   server does not let the page read it (CORS) *)
#pub fun fetch_header
  {name_loc:agz}{name_len:pos}{out_loc:agz}{out_size:pos}
  (handle: Int, name: !$A.borrow(byte, name_loc, name_len), name_len: int name_len,
   out: !$A.arr(byte, out_loc, out_size), out_size: int out_size)
  : [k:nat | k <= out_size] int k

(* As fetch_claim, with the response's ETag header written to etag:
   its length, at most etag_size, and 0 when the response has none, it
   is longer, or the server does not let the page read it *)
#pub fun fetch_claim_tagged
  {etag_loc:agz}{etag_size:pos}
  (handle: Int, etag: !$A.arr(byte, etag_loc, etag_size), etag_size: int etag_size)
  : $R.option(@([s:int] int s, [k:nat | k <= etag_size] int k, [k:nat] dblob(k)))

(* The body of a pending fetch response, as a file held by JS: its bytes
   never pass through wasm memory. Consumes the response like a claim (the
   status is taken first); none when the request failed. *)
#pub fun fetch_claim_file
  (handle: Int): $R.option(@([s:int] int s, [n:nat] infile(n)))

#pub fun on_fetch_complete
  (resolver_id: int, handle: Int)
  : void = "ext#bats_on_fetch_complete"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_js_fetch(void*, int, int);
extern int bats_js_fetch_status(int);
extern void bats_js_fetch_send(void*, int, void*, int, void*, int, void*, int, void*, int, int);
extern void bats_js_fetch_request(void*, int, void*, int, void*, int, void*, int, int);
extern int bats_js_fetch_header(int, void*, int, void*, int);
extern int bats_js_fetch_file(int);
/* The response's ETag header, as fetch_header reads it */
static int bats_fetch_etag(int handle, void *out, int out_size) {
  return bats_js_fetch_header(handle, (void*)"ETag", 4, out, out_size);
}
%}
extern fun _bats_js_fetch
  (url: ptr, url_len: int, resolver_id: int): void = "mac#bats_js_fetch"
extern fun _bats_js_fetch_status
  (handle: int): [s:int] int s = "mac#bats_js_fetch_status"
extern fun _bats_js_fetch_send
  (method: ptr, method_len: int, url: ptr, url_len: int,
   authorization: ptr, authorization_len: int, match: ptr, match_len: int,
   body: ptr, body_len: int, resolver_id: int): void = "mac#bats_js_fetch_send"
extern fun _bats_js_fetch_request
  (method: ptr, method_len: int, url: ptr, url_len: int,
   headers: ptr, headers_len: int, body: ptr, body_len: int,
   resolver_id: int): void = "mac#bats_js_fetch_request"
extern fun _bats_js_fetch_header
  (handle: int, name: ptr, name_len: int, out: ptr, out_size: int): int = "mac#bats_js_fetch_header"
extern fun _bats_js_fetch_file
  (handle: int): [v:int] int v = "mac#bats_js_fetch_file"
extern fun _bats_fetch_etag
  (handle: int, etag: ptr, etag_size: int): int = "mac#bats_fetch_etag"
end

implement fetch{lb}{n}(url, url_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_fetch(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end, url_len,
    id)
in p end

implement fetch_claim(handle) = let
  (* The status is taken first: JS drops it when the body is claimed *)
  val status = _bats_js_fetch_status(handle)
in
  case+ blob_claim(handle) of
  | ~$R.none() => $R.none()
  | ~$R.some(b) => $R.some(@(status, b))
end

implement fetch_send{method_loc}{method_len}{url_loc}{url_len}
  {authorization_loc}{authorization_size}{authorization_len}
  {match_loc}{match_size}{match_len}{body_loc}{body_size}{body_len}
  (method, method_len, url, url_len, authorization, authorization_len,
   match, match_len, body, body_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_fetch_send(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(method) end, method_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end, url_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(authorization) end, authorization_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(match) end, match_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(body) end, body_len,
    id)
in p end

implement fetch_claim_tagged{etag_loc}{etag_size}(handle, etag, etag_size) = let
  (* The ETag and the status are taken first: JS drops them when the
     body is claimed *)
  val etag_written = _bats_fetch_etag(handle,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(etag) end, etag_size)
  val etag_len = g1ofg0(etag_written)
  val status = _bats_js_fetch_status(handle)
in
  case+ blob_claim(handle) of
  | ~$R.none() => $R.none()
  | ~$R.some(b) =>
    if etag_len < 0 then $R.some(@(status, 0, b))
    else if etag_len > etag_size then $R.some(@(status, 0, b))
    else $R.some(@(status, etag_len, b))
end

implement fetch_request{method_loc}{method_len}{url_loc}{url_len}
  {headers_loc}{headers_size}{headers_len}{body_loc}{body_size}{body_len}
  (method, method_len, url, url_len, headers, headers_len, body, body_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_fetch_request(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(method) end, method_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end, url_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(headers) end, headers_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(body) end, body_len,
    id)
in p end

implement fetch_header{name_loc}{name_len}{out_loc}{out_size}
  (handle, name, name_len, out, out_size) = let
  val written = g1ofg0(_bats_js_fetch_header(handle,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(name) end, name_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end, out_size))
in
  if written < 0 then 0
  else if written > out_size then 0
  else written
end

(* JS moves the body from the pending blobs to the pending files, under a
   new file handle (0 when there is none), and file_claim checks it *)
implement fetch_claim_file(handle) = let
  val status = _bats_js_fetch_status(handle)
in
  case+ file_claim(_bats_js_fetch_file(handle)) of
  | ~$R.none() => $R.none()
  | ~$R.some(f) => $R.some(@(status, f))
end

implement on_fetch_complete(resolver_id, handle) =
  $P.fire(resolver_id, handle)

end (* #target wasm *)
