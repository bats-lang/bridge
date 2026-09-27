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
   file_store. Its reads are in range by type. *)
#pub abstype infile(n:int) = ptr

#pub fun file_open
  : {li:agz}{ni:pos}
  (!$A.borrow(byte, li, ni), int ni) -> $P.promise_pending(Int)

(* The file an open promise resolved with, or none when the open failed
   (handle 0) or the handle is not an open file: JS's word is checked
   here, once *)
#pub fun file_claim
  (handle: Int): $R.option([n:nat] infile(n))

#pub fun file_size {n:nat} (f: infile(n)): int n

(* out[0, len) := the file's bytes [file_offset, file_offset + len) *)
#pub fun file_read
  {n:nat}{o,k:nat | o + k <= n}{l:agz}{m:pos | k <= m}
  (f: infile(n), file_offset: int o,
   out: !$A.arr(byte, l, m), len: int k): void

#pub fun file_close {n:nat} (f: infile(n)): void

#pub fun file_store
  {l:agz}{n:pos}
  (!$A.borrow(byte, l, n), int n): infile(n)

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
extern int bats_js_file_size(int);
extern void bats_js_file_read(int, int, int, void*);
extern void bats_js_file_close(int);
extern int bats_js_file_store(void*, int);
%}
extern fun _bats_js_file_open
  (id: ptr, id_len: int, resolver_id: int): void = "mac#bats_js_file_open"
extern fun _bats_js_file_size
  (handle: int): [v:int] int v = "mac#bats_js_file_size"
extern fun _bats_js_file_read
  (handle: int, file_offset: int, len: int, out: ptr): void = "mac#bats_js_file_read"
extern fun _bats_js_file_close
  (handle: int): void = "mac#bats_js_file_close"
extern fun _bats_js_file_store
  (data: ptr, len: int): int = "mac#bats_js_file_store"

datatype infile_rep(int) = {n:nat} InfileRep(n) of (int, int n)
assume infile(n) = infile_rep(n)
end

implement file_open{li}{ni}(input_node_id, id_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_file_open(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(input_node_id) end, id_len, id)
in p end

implement file_claim(handle) = let
  val n = _bats_js_file_size(handle)
in
  if n >= 0 then $R.some(InfileRep(handle, n)) else $R.none()
end

implement file_size{n}(f) = let
  val InfileRep(_, n) = f
in n end

implement file_read{n}{o,k}{l}{m}(f, file_offset, out, len) = let
  val InfileRep(h, _) = f
in
  _bats_js_file_read(h, file_offset, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end)
end

implement file_close{n}(f) = let
  val InfileRep(h, _) = f
in _bats_js_file_close(h) end

implement file_store{l}{n}(data, len) =
  InfileRep(_bats_js_file_store(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end, len), len)

implement on_file_open(resolver_id, handle) =
  $P.fire(resolver_id, handle)

end (* #target wasm *)
