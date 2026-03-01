(* idb -- IndexedDB key-value storage for bridge *)

#include "share/atspre_staload.hats"

#use array as A
#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

#pub fun idb_put
  {lk:agz}{nk:pos}{lv:agz}{nv:nat}
  (key: !$A.borrow(byte, lk, nk), key_len: int nk,
   val_data: !$A.borrow(byte, lv, nv), val_len: int nv)
  : $P.promise(int, $P.Pending)

#pub fun idb_get
  {lk:agz}{nk:pos}
  (key: !$A.borrow(byte, lk, nk), key_len: int nk)
  : $P.promise(int, $P.Pending)

#pub fun idb_get_result
  {n:pos | n <= 1048576}
  (len: int n): [l:agz] $A.arr(byte, l, n)

#pub fun idb_delete
  {lk:agz}{nk:pos}
  (key: !$A.borrow(byte, lk, nk), key_len: int nk)
  : $P.promise(int, $P.Pending)

#pub fun idb_list_keys
  {lb:agz}{n:nat}
  (prefix: !$A.borrow(byte, lb, n), prefix_len: int n)
  : $P.promise(int, $P.Pending)

#pub fun idb_list_keys_result
  {n:pos | n <= 1048576}
  (len: int n): [l:agz] $A.arr(byte, l, n)

#pub fun idb_delete_database(): void

#pub fun on_idb_fire
  (resolver_id: int, status: int): void = "ext#bats_idb_fire"

#pub fun on_idb_fire_get
  (resolver_id: int, data_len: int): void = "ext#bats_idb_fire_get"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

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
  (prefix: ptr, prefix_len: int, resolver_id: int)
  : void = "mac#bats_idb_js_list_keys"

implement idb_put{lk}{nk}{lv}{nv}(key, key_len, val_data, val_len) = let
  val @(p, r) = $P.create<int>()
  val id = $P.stash(r)
  val () = _bats_idb_js_put(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(val_data) end, val_len,
    id)
in p end

implement idb_get{lk}{nk}(key, key_len) = let
  val @(p, r) = $P.create<int>()
  val id = $P.stash(r)
  val () = _bats_idb_js_get(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    id)
in p end

implement idb_get_result{n}(len) =
  stash_read(stash_get_int(1), len)

implement idb_delete{lk}{nk}(key, key_len) = let
  val @(p, r) = $P.create<int>()
  val id = $P.stash(r)
  val () = _bats_idb_js_delete(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    id)
in p end

implement idb_list_keys{lb}{n}(prefix, prefix_len) = let
  val @(p, r) = $P.create<int>()
  val id = $P.stash(r)
  val () = _bats_idb_js_list_keys(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(prefix) end, prefix_len,
    id)
in p end

implement idb_list_keys_result{n}(len) =
  stash_read(stash_get_int(1), len)

implement on_idb_fire(resolver_id, status) =
  $P.fire(resolver_id, status)

implement on_idb_fire_get(resolver_id, data_len) =
  $P.fire(resolver_id, data_len)

extern fun _bats_js_idb_delete_database
  (): void = "mac#bats_js_idb_delete_database"

implement idb_delete_database() = _bats_js_idb_delete_database()

end (* #target wasm *)
