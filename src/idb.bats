(* idb -- IndexedDB key-value storage for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* Whether a write (a put or a delete) was kept. JS's answer is decoded
   here, once: anything but its 0 is NotStored (the database could not
   be opened, or the transaction aborted, as it does when storage is
   full). *)
#pub datatype stored =
  | Stored
  | NotStored

(* What a read found. A read that failed is Unreadable, never Absent, so
   a caller cannot take it for an empty value and write a default over
   data it could not see. Linear: Found holds a blob JS keeps until it
   is freed, so the one consumer takes it apart with case+ ~ and frees
   the blob; a lookup no consumer takes is freed by promise's dispose. *)
#pub datavtype lookup =
  | Found of ([n:nat] dblob(n))
  | Absent       (* nothing is stored there *)
  | Unreadable   (* it could not be read *)

(* Stores the value under the key *)
#pub fun idb_put
  : {lk:agz}{nk:pos}{lv:agz}{nv:nat}
  (!$A.borrow(byte, lk, nk), int nk,
   !$A.borrow(byte, lv, nv), int nv) -> $P.promise(stored, $P.Chained)

(* The value stored under the key. Each value is its own blob, so
   concurrent gets cannot overwrite each other's data *)
#pub fun idb_get
  : {lk:agz}{nk:pos}
  (!$A.borrow(byte, lk, nk), int nk) -> $P.promise(lookup, $P.Chained)

(* Deletes the key *)
#pub fun idb_delete
  : {lk:agz}{nk:pos}
  (!$A.borrow(byte, lk, nk), int nk) -> $P.promise(stored, $P.Chained)

(* The keys starting with the prefix, each as a u16le length and its
   bytes, Found as one blob; Absent when there are none *)
#pub fun idb_list_keys
  : {lb:agz}{n:nat}
  (!$A.borrow(byte, lb, n), int n) -> $P.promise(lookup, $P.Chained)

(* A write's promise of JS's code (0, or -1 when it failed), decoded:
   file.bats's writes to IndexedDB answer as idb_put's do *)
#pub fun stored_decode
  (p: $P.promise(Int, $P.Pending)): $P.promise(stored, $P.Chained)

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

(* JS's codes for a write: 0 stored, anything else (its -1) not *)
fn _stored (code: Int): stored =
  if code = 0 then Stored() else NotStored()

(* A write's outcome nobody took: nothing to free. ATS2 resolves a
   template's instances in file order, so each dispose comes before its
   first use. *)
implement $P.dispose<stored>(_) = ()

(* JS's codes for a read: a blob's handle (positive), 0 nothing there,
   anything else (its -1) unreadable. A handle JS did not hand out is
   unreadable too: its word is checked here, once *)
fn _lookup (code: Int): lookup =
  if code = 0 then Absent()
  else if code < 0 then Unreadable()
  else (case+ blob_claim(code) of
    | ~$R.some(blob) => Found(blob)
    | ~$R.none() => Unreadable())

(* A lookup nobody took: its blob is freed *)
implement $P.dispose<lookup>(found) =
  case+ found of
  | ~Found(blob) => blob_free(blob)
  | ~Absent() => ()
  | ~Unreadable() => ()

implement stored_decode(p) =
  $P.and_then<Int><stored>(p, llam (code) => $P.ret<stored>(_stored(code)))

(* A read's promise, decoded *)
fn _lookup_promise (p: $P.promise(Int, $P.Pending)): $P.promise(lookup, $P.Chained) =
  $P.and_then<Int><lookup>(p, llam (code) => $P.ret<lookup>(_lookup(code)))

implement idb_put{lk}{nk}{lv}{nv}(key, key_len, val_data, val_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_idb_js_put(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(val_data) end, val_len,
    id)
in stored_decode(p) end

implement idb_get{lk}{nk}(key, key_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_idb_js_get(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    id)
in _lookup_promise(p) end

implement idb_delete{lk}{nk}(key, key_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_idb_js_delete(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    id)
in stored_decode(p) end

implement idb_list_keys{lb}{n}(pfx, pfx_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_idb_js_list_keys(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(pfx) end, pfx_len,
    id)
in _lookup_promise(p) end

implement on_idb_fire(resolver_id, status) =
  $P.fire(resolver_id, status)

implement on_idb_fire_get(resolver_id, handle) =
  $P.fire(resolver_id, handle)

implement idb_delete_database() = _bats_js_idb_delete_database()

end (* #target wasm *)
