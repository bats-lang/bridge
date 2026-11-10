(* outside -- bytes that came from outside the program, with the proof (keyword: outside read) *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"
staload "./idb.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* OUTSIDE_READ(cs): the cells cs are bytes of an outside source, read whole
   by bridge's JS. The sources are a file the user picked or dropped, the body
   of an http(s) GET, the browser's decompression of outside bytes, and JS's
   own copies of those (the second IndexedDB database, bats-outside). Bytes the
   program wrote never have it: file_store and decompress of a plain borrow,
   file_idb_get from kv, a page read, the clipboard, an event's payload and a
   value of idb_put keep their ordinary handles. The one place that makes the
   proof is this file's $UNSAFE region, below: the assumption that is tested
   (tests/dynamic/outside-store, outside-fetch-scheme and the book cases) is
   that JS wrote exactly len bytes from an outside table into the cells and
   nothing else. After barr_set the cells are others, so the proof is not
   theirs; a copy of an outside array (barr_copy) has the same cells, which
   are outside bytes, as they are. *)
#pub absprop OUTSIDE_READ(cs: $A.cells)

(* A file of n bytes from an outside source, held by JS in a table of its own
   until closed. Linear, like infile; no function turns an infile into one *)
#pub absvt@ype infile_outside(n:int) = @(int, int)

(* A blob of n bytes from an outside source, held by JS until freed *)
#pub absvtype dblob_outside(n:int) = ptr

(* What opening a picked or dropped file found: as opened, for an outside
   file. Linear: one no consumer takes is closed by promise's dispose *)
#pub datavtype opened_outside =
  | OpenedOutside of ([n:nat] infile_outside(n))
  | NotOpenedOutside
  | OpenFailedOutside

(* What decompress_outside gave: as decompressed *)
#pub datavtype decompressed_outside =
  | DecompressedOutside of ([n:nat] dblob_outside(n))
  | DecompressFailedOutside

(* What file_idb_get_outside found: as file_lookup *)
#pub datavtype file_lookup_outside =
  | FoundOutside of ([n:nat] infile_outside(n))
  | NotFoundOutside
  | LookupFailedOutside

(* What fetch_outside came to: the body of a GET whose final URL is http: or
   https:, or none (a URL of another scheme, a redirect to one, a network
   failure) *)
#pub datavtype fetched_outside =
  | FetchedOutside of ([n:nat] dblob_outside(n))
  | NotFetchedOutside

(* Reads file i of those picked in the file input with that id, as
   file_open_at does, for an outside file *)
#pub fun file_open_at_outside
  {li:agz}{ni:pos}
  (!$A.borrow(byte, li, ni), int ni, int): $P.promise(opened_outside, $P.Chained)

(* Reads file i of the last drop, as dropped_open_at does *)
#pub fun dropped_open_at_outside (int): $P.promise(opened_outside, $P.Chained)

(* A GET with no request body and no headers set by the app. JS refuses a URL
   whose scheme is not http: or https: before it fetches, and gives nothing
   when Response.url (the final URL, after redirects) is empty or not http: or
   https:. A data: URL is the bytes themselves and a blob: URL can hold bytes
   the program stored, so neither counts. A response from the app's own origin
   does count: the proof says where the bytes came from, not who wrote them on
   the server. The body goes into the outside blob table *)
#pub fun fetch_outside
  {lb:agz}{n:pos}
  (!$A.borrow(byte, lb, n), int n): $P.promise(fetched_outside, $P.Chained)

(* The browser's decompression of outside bytes. The program chooses only the
   method, and Uncompressed passes the bytes through unchanged *)
#pub fun decompress_outside
  {lb:agz}{n:pos}{cs:$A.cells}
  (from: OUTSIDE_READ(cs) | data: !$A.cborrow(lb, n, cs), data_len: int n,
   method: compression): $P.promise(decompressed_outside, $P.Chained)

(* A file of outside bytes held by JS, from outside bytes in memory *)
#pub fun file_store_outside
  {l:agz}{n:pos}{cs:$A.cells}
  (from: OUTSIDE_READ(cs) | data: !$A.cborrow(l, n, cs), n: int n): infile_outside(n)

(* Stores f's bytes in the second IndexedDB database (bats-outside, version 1,
   one store files, opened by its own openOutsideDB), from the JS side. Only
   this writes it, so idb_put cannot forge an outside copy; the bats database
   and its version are unchanged *)
#pub fun file_idb_put_outside
  {lk:agz}{nk:pos}{n:nat}
  (key: !$A.borrow(byte, lk, nk), key_len: int nk, f: !infile_outside(n))
  : $P.promise(stored, $P.Chained)

#pub fun file_idb_get_outside
  {lk:agz}{nk:pos}
  (key: !$A.borrow(byte, lk, nk), key_len: int nk)
  : $P.promise(file_lookup_outside, $P.Chained)

#pub fun file_idb_delete_outside
  {lk:agz}{nk:pos}
  (key: !$A.borrow(byte, lk, nk), key_len: int nk)
  : $P.promise(stored, $P.Chained)

(* The operations an ordinary file has, for an outside one *)
#pub fun file_size_outside {n:nat} (f: !infile_outside(n)): int n

#pub fun file_close_outside {n:nat} (f: infile_outside(n)): void

(* The name the file had where it came from, as a blob; none when it has none *)
#pub fun file_name_outside {n:nat} (f: !infile_outside(n)): $R.option([k:nat] dblob(k))

#pub fun file_blob_url_outside
  {n:nat}{o,k:nat | o + k <= n; k > 0}{lm:agz}{nm:pos}
  (f: !infile_outside(n), file_offset: int o, len: int k,
   mime: !$A.borrow(byte, lm, nm), mime_len: int nm)
  : $R.option([u:nat] dblob(u))

(* out[0, len) := the file's bytes [file_offset, file_offset + len), with no
   proof about them *)
#pub fun file_read_plain_outside
  {n:nat}{o,k:nat | o + k <= n}{l:agz}{ow:addr}{m:pos | k <= m}
  (f: !infile_outside(n), file_offset: int o,
   out: !$A.arrx(byte, l, m, ow), len: int k): void

(* Reads the file's bytes [file_offset, file_offset + k) into a piece of an
   arena (or any arrx), lent as a barr whose cells are known to be the
   source's. Take the piece back with barr_to_arrx *)
#pub fun file_read_outside
  {n:nat}{f:nat}{k:pos | f + k <= n}{l:agz}{o:addr}
  (file: !infile_outside(n), offset: int f, out: $A.arrx(byte, l, k, o), len: int k)
  : [cs:$A.cells] (OUTSIDE_READ(cs), $A.CLEN(cs, k), $A.arrx_lent(l, k, o) | $A.barr(l, k, cs))

#pub fun blob_len_outside {n:nat} (b: !dblob_outside(n)): int n

#pub fun blob_free_outside {n:nat} (b: dblob_outside(n)): void

#pub fun blob_read_plain_outside
  {n:nat}{o,k:nat | o + k <= n}{l:agz}{ow:addr}{m:pos | k <= m}
  (b: !dblob_outside(n), blob_offset: int o,
   out: !$A.arrx(byte, l, m, ow), len: int k): void

(* The whole blob, as file_read_outside gives a file's bytes *)
#pub fun blob_read_outside
  {n:pos}{l:agz}{o:addr}
  (b: !dblob_outside(n), out: $A.arrx(byte, l, n, o), len: int n)
  : [cs:$A.cells] (OUTSIDE_READ(cs), $A.CLEN(cs, n), $A.arrx_lent(l, n, o) | $A.barr(l, n, cs))

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

$UNSAFE begin
%{
extern void bats_js_file_open_at_outside(void*, int, int, int);
extern void bats_js_dropped_open_at_outside(int, int);
extern int bats_js_file_claim_outside(int);
extern void bats_js_file_read_outside(int, int, int, void*);
extern void bats_js_file_close_outside(int);
extern int bats_js_file_store_outside(void*, int);
extern int bats_js_file_name_outside(int);
extern int bats_js_file_blob_url_outside(int, int, int, void*, int);
extern void bats_js_file_idb_put_outside(void*, int, int, int);
extern void bats_js_file_idb_get_outside(void*, int, int);
extern void bats_js_file_idb_delete_outside(void*, int, int);
extern void bats_js_decompress_outside(void*, int, int, int);
extern int bats_js_blob_claim_outside(int);
extern void bats_js_blob_read_outside(int, int, int, void*);
extern void bats_js_blob_free_outside(int);
extern void bats_js_fetch_outside(void*, int, int);
%}
extern fun _bats_js_file_open_at_outside
  (id: ptr, id_len: int, i: int, resolver_id: int): void = "mac#bats_js_file_open_at_outside"
extern fun _bats_js_dropped_open_at_outside
  (i: int, resolver_id: int): void = "mac#bats_js_dropped_open_at_outside"
extern fun _bats_js_file_claim_outside
  (handle: int): [v:int] int v = "mac#bats_js_file_claim_outside"
extern fun _bats_js_file_read_outside
  (handle: int, file_offset: int, len: int, out: ptr): void = "mac#bats_js_file_read_outside"
extern fun _bats_js_file_close_outside
  (handle: int): void = "mac#bats_js_file_close_outside"
extern fun _bats_js_file_store_outside
  (data: ptr, len: int): int = "mac#bats_js_file_store_outside"
extern fun _bats_js_file_name_outside
  (handle: int): [v:int] int v = "mac#bats_js_file_name_outside"
extern fun _bats_js_file_blob_url_outside
  (handle: int, file_offset: int, len: int, mime: ptr, mime_len: int)
  : [v:int] int v = "mac#bats_js_file_blob_url_outside"
extern fun _bats_js_file_idb_put_outside
  (key: ptr, key_len: int, handle: int, resolver_id: int): void = "mac#bats_js_file_idb_put_outside"
extern fun _bats_js_file_idb_get_outside
  (key: ptr, key_len: int, resolver_id: int): void = "mac#bats_js_file_idb_get_outside"
extern fun _bats_js_file_idb_delete_outside
  (key: ptr, key_len: int, resolver_id: int): void = "mac#bats_js_file_idb_delete_outside"
extern fun _bats_js_decompress_outside
  (data: ptr, data_len: int, method: int, resolver_id: int): void = "mac#bats_js_decompress_outside"
extern fun _bats_js_blob_claim_outside
  (handle: int): [v:int] int v = "mac#bats_js_blob_claim_outside"
extern fun _bats_js_blob_read_outside
  (handle: int, blob_offset: int, len: int, out: ptr): void = "mac#bats_js_blob_read_outside"
extern fun _bats_js_blob_free_outside
  (handle: int): void = "mac#bats_js_blob_free_outside"
extern fun _bats_js_fetch_outside
  (url: ptr, url_len: int, resolver_id: int): void = "mac#bats_js_fetch_outside"

(* The one place OUTSIDE_READ is made (keyword: outside read): the cells of an
   array JS has just written from an outside table *)
extern praxi outside_read_made {cs:$A.cells} (): OUTSIDE_READ(cs)

(* The JS handle and the size: flat, no cell to allocate *)
assume infile_outside(n) = @(int, int n)

datavtype outside_blob_rep(int) = {n:nat} OutsideBlobRep(n) of (int, int n)
assume dblob_outside(n) = outside_blob_rep(n)
end

(* A claimed outside file: JS's code is the handle (positive) and the size
   comes from the claim. A handle JS did not hand out is none *)
fn _claimed_file_outside (code: int): $R.option([n:nat] infile_outside(n)) = let
  val n = _bats_js_file_claim_outside(code)
in
  if n >= 0 then $R.some(@(code, n)) else $R.none()
end

fn _claimed_blob_outside (code: int): $R.option([n:nat] dblob_outside(n)) = let
  val n = _bats_js_blob_claim_outside(code)
in
  if n >= 0 then $R.some(OutsideBlobRep(code, n)) else $R.none()
end

(* The name or URL of an outside file is not an outside byte: an ordinary
   blob, claimed with the ordinary table *)
fn _claimed_blob (code: int): $R.option([n:nat] dblob(n)) =
  blob_claim($UNSAFE begin $UNSAFE.cast{blob_handle}(code) end)

(* JS's codes for an open: a file's handle (positive), 0 no such file,
   anything else (its -1) a read that failed. A handle JS did not hand out is
   a failure too *)
fn _opened_outside (code: Int): opened_outside =
  if code = 0 then NotOpenedOutside()
  else if code < 0 then OpenFailedOutside()
  else (case+ _claimed_file_outside(code) of
    | ~$R.some(f) => OpenedOutside(f)
    | ~$R.none() => OpenFailedOutside())

(* A file nobody took: closed *)
implement $P.dispose<opened_outside>(found) =
  case+ found of
  | ~OpenedOutside(f) => file_close_outside(f)
  | ~NotOpenedOutside() => ()
  | ~OpenFailedOutside() => ()

fn _opened_outside_promise (p: $P.promise(Int, $P.Pending)): $P.promise(opened_outside, $P.Chained) =
  $P.and_then<Int><opened_outside>(p, llam (code) => $P.ret<opened_outside>(_opened_outside(code)))

implement file_open_at_outside{li}{ni}(input_node_id, id_len, i) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_file_open_at_outside(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(input_node_id) end, id_len, i, id)
in _opened_outside_promise(p) end

implement dropped_open_at_outside(i) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_dropped_open_at_outside(i, id)
in _opened_outside_promise(p) end

implement file_size_outside{n}(f) = f.1

implement file_close_outside{n}(f) = _bats_js_file_close_outside(f.0)

implement file_name_outside{n}(f) = _claimed_blob(_bats_js_file_name_outside(f.0))

implement file_blob_url_outside{n}{o,k}{lm}{nm}(f, file_offset, len, mime, mime_len) =
  _claimed_blob(_bats_js_file_blob_url_outside(f.0, file_offset, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(mime) end, mime_len))

implement file_read_plain_outside{n}{o,k}{l}{ow}{m}(f, file_offset, out, len) =
  _bats_js_file_read_outside(f.0, file_offset, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end)

implement file_read_outside{n}{f}{k}{l}{o}(file, offset, out, len) = let
  val () = _bats_js_file_read_outside(file.0, offset, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end)
  val [cs:$A.cells] @(pfc, pflent | a) = $A.barr_of_arrx(out)
  prval pfo = outside_read_made{cs}()
in @(pfo, pfc, pflent | a) end

implement file_store_outside{l}{n}{cs}(pf | data, len) =
  @(_bats_js_file_store_outside(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end, len), len)

implement blob_len_outside{n}(b) = let
  val+ OutsideBlobRep(_, n) = b
in n end

implement blob_free_outside{n}(b) = let
  val+ ~OutsideBlobRep(h, _) = b
in _bats_js_blob_free_outside(h) end

implement blob_read_plain_outside{n}{o,k}{l}{ow}{m}(b, blob_offset, out, len) = let
  val+ OutsideBlobRep(h, _) = b
in
  _bats_js_blob_read_outside(h, blob_offset, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end)
end

implement blob_read_outside{n}{l}{o}(b, out, len) = let
  val+ OutsideBlobRep(h, _) = b
  val () = _bats_js_blob_read_outside(h, 0, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end)
  val [cs:$A.cells] @(pfc, pflent | a) = $A.barr_of_arrx(out)
  prval pfo = outside_read_made{cs}()
in @(pfo, pfc, pflent | a) end

(* JS's codes for a decompression: a blob's handle (positive), anything else
   (its 0) failed *)
fn _decompressed_outside (code: Int): decompressed_outside =
  if code <= 0 then DecompressFailedOutside()
  else (case+ _claimed_blob_outside(code) of
    | ~$R.some(blob) => DecompressedOutside(blob)
    | ~$R.none() => DecompressFailedOutside())

(* A result nobody took: its blob is freed *)
implement $P.dispose<decompressed_outside>(result) =
  case+ result of
  | ~DecompressedOutside(blob) => blob_free_outside(blob)
  | ~DecompressFailedOutside() => ()

(* The codes of decompress's methods: 0 stored, 1 gzip, 2 deflate, 8 raw deflate *)
fn _method_code (method: compression): int =
  case+ method of
  | Uncompressed() => 0
  | Gzip() => 1
  | Deflate() => 2
  | DeflateRaw() => 8

implement decompress_outside{lb}{n}{cs}(pf | data, data_len, method) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_decompress_outside(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end,
    data_len, _method_code(method), id)
in $P.and_then<Int><decompressed_outside>(p, llam (code) =>
  $P.ret<decompressed_outside>(_decompressed_outside(code))) end

(* JS's codes for a fetch: a body's handle (positive), 0 none *)
fn _fetched_outside (code: Int): fetched_outside =
  if code <= 0 then NotFetchedOutside()
  else (case+ _claimed_blob_outside(code) of
    | ~$R.some(blob) => FetchedOutside(blob)
    | ~$R.none() => NotFetchedOutside())

(* A body nobody took: freed *)
implement $P.dispose<fetched_outside>(result) =
  case+ result of
  | ~FetchedOutside(blob) => blob_free_outside(blob)
  | ~NotFetchedOutside() => ()

implement fetch_outside{lb}{n}(url, url_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_fetch_outside(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end, url_len, id)
in $P.and_then<Int><fetched_outside>(p, llam (code) =>
  $P.ret<fetched_outside>(_fetched_outside(code))) end

(* JS's codes for a read: a file's handle (positive), 0 nothing there,
   anything else (its -1) unreadable. A handle JS did not hand out is
   unreadable too *)
fn _file_lookup_outside (code: Int): file_lookup_outside =
  if code = 0 then NotFoundOutside()
  else if code < 0 then LookupFailedOutside()
  else (case+ _claimed_file_outside(code) of
    | ~$R.some(f) => FoundOutside(f)
    | ~$R.none() => LookupFailedOutside())

(* A file nobody took: closed *)
implement $P.dispose<file_lookup_outside>(found) =
  case+ found of
  | ~FoundOutside(f) => file_close_outside(f)
  | ~NotFoundOutside() => ()
  | ~LookupFailedOutside() => ()

implement file_idb_put_outside{lk}{nk}{n}(key, key_len, f) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_file_idb_put_outside(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len, f.0, id)
in stored_decode(p) end

implement file_idb_get_outside{lk}{nk}(key, key_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_file_idb_get_outside(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len, id)
in $P.and_then<Int><file_lookup_outside>(p, llam (code) =>
  $P.ret<file_lookup_outside>(_file_lookup_outside(code))) end

implement file_idb_delete_outside{lk}{nk}(key, key_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_file_idb_delete_outside(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len, id)
in stored_decode(p) end

end (* #target wasm *)
