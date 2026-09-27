(* idb -- IndexedDB key-value storage for bridge *)

#include "share/atspre_staload.hats"

#use array as A
#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

#pub fun idb_put
  : {lk:agz}{nk:pos}{lv:agz}{nv:nat}
  (!$A.borrow(byte, lk, nk), int nk,
   !$A.borrow(byte, lv, nv), int nv) -> $P.promise_pending(Int)

(* The value stored under the key: the promise resolves with a handle
   to claim with blob_claim (decompress.bats), 0 when there is none.
   Each result is its own blob, so concurrent gets cannot overwrite
   each other's data *)
#pub fun idb_get
  : {lk:agz}{nk:pos}
  (!$A.borrow(byte, lk, nk), int nk) -> $P.promise_pending(Int)

#pub fun idb_delete
  : {lk:agz}{nk:pos}
  (!$A.borrow(byte, lk, nk), int nk) -> $P.promise_pending(Int)

(* The keys starting with the prefix, each as a u16le length and its
   bytes: the promise resolves with a blob handle as idb_get's does, 0
   when there are none *)
#pub fun idb_list_keys
  : {lb:agz}{n:nat}
  (!$A.borrow(byte, lb, n), int n) -> $P.promise_pending(Int)

#pub fun idb_delete_database(): void

#pub fun on_idb_fire
  (resolver_id: int, status: Int): void = "ext#bats_idb_fire"

#pub fun on_idb_fire_get
  (resolver_id: int, handle: Int): void = "ext#bats_idb_fire_get"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_idb_js_put(void*, int, void*, int, int);
extern void bats_idb_js_get(void*, int, int);
extern void bats_idb_js_delete(void*, int, int);
extern void bats_idb_js_list_keys(void*, int, int);
extern void bats_js_idb_delete_database(void);
%}
extern fun _bats_idb_js_put
  (key: ptr, key_len: int, val_data: ptr, val_len: int, resolver_id: int)
  : void = "mac#bats_idb_js_put"
extern fun _bats_idb_js_get
  (key: ptr, key_len: int, resolver_id: int)
  : void = "mac#bats_idb_js_get"
extern fun _bats_idb_js_delete
  (key: ptr, key_len: int, resolver_id: int)
  : void = "mac#bats_idb_js_delete"
extern fun _bats_idb_js_list_keys
  (pfx: ptr, pfx_len: int, resolver_id: int)
  : void = "mac#bats_idb_js_list_keys"
extern fun _bats_js_idb_delete_database
  (): void = "mac#bats_js_idb_delete_database"
end

implement idb_put{lk}{nk}{lv}{nv}(key, key_len, val_data, val_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_idb_js_put(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(val_data) end, val_len,
    id)
in p end

implement idb_get{lk}{nk}(key, key_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_idb_js_get(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    id)
in p end

implement idb_delete{lk}{nk}(key, key_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_idb_js_delete(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    id)
in p end

implement idb_list_keys{lb}{n}(pfx, pfx_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_idb_js_list_keys(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(pfx) end, pfx_len,
    id)
in p end

implement on_idb_fire(resolver_id, status) =
  $P.fire(resolver_id, status)

implement on_idb_fire_get(resolver_id, handle) =
  $P.fire(resolver_id, handle)

implement idb_delete_database() = _bats_js_idb_delete_database()

end (* #target wasm *)
