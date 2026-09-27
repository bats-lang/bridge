(* file -- file input/read/close for bridge *)

#include "share/atspre_staload.hats"

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
   when the store failed *)
#pub fun file_idb_put
  {lk:agz}{nk:pos}{n:nat}
  (key: !$A.borrow(byte, lk, nk), key_len: int nk, f: !infile(n))
  : $P.promise_pending(Int)

(* The bytes stored under key (by file_idb_put) as a file, from the JS
   side; the promise resolves with a handle to claim with file_claim,
   which is none when nothing is stored there *)
#pub fun file_idb_get
  {lk:agz}{nk:pos}
  (key: !$A.borrow(byte, lk, nk), key_len: int nk)
  : $P.promise_pending(Int)

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

implement on_file_open(resolver_id, handle) =
  $P.fire(resolver_id, handle)

end (* #target wasm *)
