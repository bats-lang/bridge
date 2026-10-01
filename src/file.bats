(* file -- file input/read/close for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* A file of n bytes held by JS: one the user picked (claimed from the
   handle its open promise resolves with), or bytes stored with
   file_store. Its reads are in range by type. It is linear: JS holds
   each file under one handle, claimed at most once, and file_close
   consumes the only infile of it, so a closed file cannot be read. *)
#pub absvt@ype infile(n:int) = @(int, int)

#pub fun file_open
  : {li:agz}{ni:pos}
  (!$A.borrow(byte, li, ni), int ni) -> $P.promise_pending(Int)

(* The file an open promise resolved with, or none when the open failed
   (handle 0) or the handle is not a file waiting to be claimed (JS
   hands each file out once): JS's word is checked here, once *)
#pub fun file_claim
  (handle: Int): $R.option([n:nat] infile(n))

#pub fun file_size {n:nat} (f: !infile(n)): int n

(* out[0, len) := the file's bytes [file_offset, file_offset + len) *)
#pub fun file_read
  {n:nat}{o,k:nat | o + k <= n}{l:agz}{ow:addr}{m:pos | k <= m}
  (f: !infile(n), file_offset: int o,
   out: !$A.arrx(byte, l, m, ow), len: int k): void

(* Releases the file on the JS side *)
#pub fun file_close {n:nat} (f: infile(n)): void

(* A file holding data[0, n); it is claimed as it is made *)
#pub fun file_store
  {l:agz}{n:pos}
  (!$A.borrow(byte, l, n), int n): infile(n)

(* Stores f's bytes in IndexedDB under key, from the JS side (the bytes
   never pass through wasm memory); the promise resolves with 0, or -1
   when the store failed (as idb_put's) *)
#pub fun file_idb_put
  {lk:agz}{nk:pos}{n:nat}
  (key: !$A.borrow(byte, lk, nk), key_len: int nk, f: !infile(n))
  : $P.promise_pending(Int)

(* The bytes stored under key (by file_idb_put) as a file, from the JS
   side; the promise resolves with a handle to claim with file_claim,
   0 when nothing is stored there, or -1 when it could not be read
   (file_claim of either is none) *)
#pub fun file_idb_get
  {lk:agz}{nk:pos}
  (key: !$A.borrow(byte, lk, nk), key_len: int nk)
  : $P.promise_pending(Int)

(* How many files are picked in the file input with that id (0 when
   there is no such input) *)
#pub fun file_count
  {li:agz}{ni:pos}
  (!$A.borrow(byte, li, ni), int ni): [v:nat] int v

(* Reads file i of those picked in the file input with that id; the
   promise resolves with a handle to claim (0 when there is no file i) *)
#pub fun file_open_at
  {li:agz}{ni:pos}
  (!$A.borrow(byte, li, ni), int ni, int): $P.promise_pending(Int)

(* How many files the last drop event carried (set when a drop
   listener's payload is made) *)
#pub fun dropped_count (): [v:nat] int v

(* Reads file i of the last drop; as file_open_at *)
#pub fun dropped_open_at (int): $P.promise_pending(Int)

(* The name the file had where it came from (a picked, dropped or
   external file), as a blob; none when it has none *)
#pub fun file_name {n:nat} (f: !infile(n)): $R.option([k:nat] dblob(k))

#pub fun on_file_open
  (resolver_id: int, handle: Int)
  : void = "ext#bats_on_file_open"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_js_file_open(void*, int, int);
extern int bats_js_file_claim(int);
extern void bats_js_file_read(int, int, int, void*);
extern void bats_js_file_close(int);
extern int bats_js_file_store(void*, int);
extern void bats_js_file_idb_put(void*, int, int, int);
extern void bats_js_file_idb_get(void*, int, int);
extern int bats_js_file_count(void*, int);
extern void bats_js_file_open_at(void*, int, int, int);
extern int bats_js_dropped_count(void);
extern void bats_js_dropped_open_at(int, int);
extern int bats_js_file_name(int);
%}
extern fun _bats_js_file_open
  (id: ptr, id_len: int, resolver_id: int): void = "mac#bats_js_file_open"
extern fun _bats_js_file_claim
  (handle: int): [v:int] int v = "mac#bats_js_file_claim"
extern fun _bats_js_file_read
  (handle: int, file_offset: int, len: int, out: ptr): void = "mac#bats_js_file_read"
extern fun _bats_js_file_close
  (handle: int): void = "mac#bats_js_file_close"
extern fun _bats_js_file_store
  (data: ptr, len: int): int = "mac#bats_js_file_store"
extern fun _bats_js_file_idb_put
  (key: ptr, key_len: int, handle: int, resolver_id: int): void = "mac#bats_js_file_idb_put"
extern fun _bats_js_file_idb_get
  (key: ptr, key_len: int, resolver_id: int): void = "mac#bats_js_file_idb_get"
extern fun _bats_js_file_count
  (id: ptr, id_len: int): [v:int] int v = "mac#bats_js_file_count"
extern fun _bats_js_file_open_at
  (id: ptr, id_len: int, i: int, resolver_id: int): void = "mac#bats_js_file_open_at"
extern fun _bats_js_dropped_count
  (): [v:int] int v = "mac#bats_js_dropped_count"
extern fun _bats_js_dropped_open_at
  (i: int, resolver_id: int): void = "mac#bats_js_dropped_open_at"
extern fun _bats_js_file_name
  (handle: int): [v:int] int v = "mac#bats_js_file_name"

(* The JS handle and the size: flat, no cell to allocate *)
assume infile(n) = @(int, int n)
end

implement file_open{li}{ni}(input_node_id, id_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_file_open(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(input_node_id) end, id_len, id)
in p end

implement file_claim(handle) = let
  val n = _bats_js_file_claim(handle)
in
  if n >= 0 then $R.some(@(handle, n)) else $R.none()
end

implement file_size{n}(f) = f.1

implement file_read{n}{o,k}{l}{ow}{m}(f, file_offset, out, len) = let
  val h = f.0
in
  _bats_js_file_read(h, file_offset, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end)
end

implement file_close{n}(f) = _bats_js_file_close(f.0)

implement file_store{l}{n}(data, len) =
  @(_bats_js_file_store(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end, len), len)

implement file_idb_put{lk}{nk}{n}(key, key_len, f) = let
  val h = f.0
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_file_idb_put(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len, h, id)
in p end

implement file_idb_get{lk}{nk}(key, key_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_file_idb_get(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len, id)
in p end

(* A count from JS, checked here once *)
fn _count {c:int} (c: int c): [v:nat] int v =
  if c > 0 then c else 0

implement file_count{li}{ni}(input_node_id, id_len) =
  _count(_bats_js_file_count(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(input_node_id) end, id_len))

implement file_open_at{li}{ni}(input_node_id, id_len, i) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_file_open_at(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(input_node_id) end, id_len, i, id)
in p end

implement dropped_count() = _count(_bats_js_dropped_count())

implement dropped_open_at(i) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_dropped_open_at(i, id)
in p end

implement file_name{n}(f) = blob_claim(_bats_js_file_name(f.0))

implement on_file_open(resolver_id, handle) =
  $P.fire(resolver_id, handle)

end (* #target wasm *)
