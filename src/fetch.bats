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

(* Whether src[i, k) has no line break (a header's value cannot hold
   one: it would end the header) *)
fun _one_line {ls:agz}{size:nat}{k:nat | k <= size}{i:nat | i <= k} .<k - i>.
  (src: !$A.borrow(byte, ls, size), k: int k, i: int i): bool =
  if i >= k then true
  else let
    val c = byte2int0($A.read<byte>(src, i))
  in if c = 10 || c = 13 then false else _one_line(src, k, i + 1) end

(* dst[at + i, at + k) := src[i, k) *)
fun _copy {ls,ld:agz}{size,m:nat}{k:nat | k <= size}{at:nat | at + k <= m}{i:nat | i <= k} .<k - i>.
  (dst: !$A.arr(byte, ld, m), at: int at, src: !$A.borrow(byte, ls, size), k: int k, i: int i): void =
  if i >= k then ()
  else let
    val () = $A.set<byte>(dst, at + i, $A.read<byte>(src, i))
  in _copy(dst, at, src, k, i + 1) end

(* dst[at, at + n) := s, n being s's length *)
fn _put {ld:agz}{m:nat}{n:nat}{at:nat | at + n <= m}
  (dst: !$A.arr(byte, ld, m), at: int at, s: string n): int(at + n) = let
  val n = g1u2i(string1_length(s))
  val () = $A.write_text(dst, at, $A.text_lit(s), n)
in at + n end

(* The lines "Authorization: <a>" and "If-Match: <t>" (each left out
   when its value is empty) written in dst, at most 26 + a + t bytes:
   their length *)
fn _header_lines {la,lt,ld:agz}{sa,st:nat}{a:nat | a <= sa}{t:nat | t <= st}{m:int | m == 27 + a + t}
  (dst: !$A.arr(byte, ld, m), authorization: !$A.borrow(byte, la, sa), a: int a,
   match: !$A.borrow(byte, lt, st), t: int t): [e:nat | e <= 26 + a + t] int e = let
  val next = (if a > 0 then let
      val at = _put(dst, 0, "Authorization: ")
      val () = _copy(dst, at, authorization, a, 0)
      val () = $A.set<byte>(dst, at + a, $A.int2byte(10))
    in at + a + 1 end
    else 0): [n:nat | n <= 16 + a] int n
in
  if t > 0 then let
    val at = _put(dst, next, "If-Match: ")
    val () = _copy(dst, at, match, t, 0)
  in at + t end
  else next
end

(* A request that is not made: its promise resolves 0, as a failed one's *)
fn _fetch_failed (): $P.promise_pending(Int) = let
  val @(p, r) = $P.create<Int>()
  val () = $P.resolve<Int>(r, 0)
in p end

(* fetch_send is fetch_request with its two headers written as lines,
   each left out when its value is empty. A value with a line break in
   it would end its header and start another, so the request is not
   made: it fails, as the browser fails one whose header it refuses *)
implement fetch_send{method_loc}{method_len}{url_loc}{url_len}
  {authorization_loc}{authorization_size}{authorization_len}
  {match_loc}{match_size}{match_len}{body_loc}{body_size}{body_len}
  (method, method_len, url, url_len, authorization, authorization_len,
   match, match_len, body, body_len) =
  if authorization_len + match_len > 1048000 then _fetch_failed()
  else if not(_one_line(authorization, authorization_len, 0)) then _fetch_failed()
  else if not(_one_line(match, match_len, 0)) then _fetch_failed()
  else let
    val headers = $A.alloc<byte>(27 + authorization_len + match_len)
    val headers_len = _header_lines(headers, authorization, authorization_len, match, match_len)
    val @(headers_frozen, headers_borrow) = $A.freeze<byte>(headers)
    val sent = fetch_request(method, method_len, url, url_len, headers_borrow, headers_len, body, body_len)
    val () = $A.drop<byte>(headers_frozen, headers_borrow)
    val () = $A.free<byte>($A.thaw<byte>(headers_frozen))
  in sent end

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
