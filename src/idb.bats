(* idb -- IndexedDB key-value storage for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* Which case of JS's answer bridge did not recognise (bats-lang/quire#354:
   an answer is never folded into another). JS gives only the codes
   below; anything else is one of these, with the code as JS gave it. *)
#pub datatype idb_unexpected =
  | UnknownCode      (* a negative code JS never gives *)
  | UnclaimedHandle  (* a positive code that is not a blob JS handed out *)

(* The causes, and what holds them (stored, lookup, updated), are linear
   (a constructor with data allocates, and wasm has no collector): the one
   consumer matches with case+ ~, or hands a cause to its _free. *)

(* Why a read found nothing it could use. JS's codes, decoded here once:
   -1 the database could not be opened, -2 the request or its transaction
   errored or aborted. *)
#pub datavtype unreadable_cause =
  | NoDatabase                                   (* indexedDB.open failed, or the database could not be used *)
  | ReadFailed                                   (* the request or its transaction errored or aborted *)
  | UnreadableUnexpected of (idb_unexpected, int) (* an answer bridge does not recognise, and its code *)

(* Why a write was not kept. JS's codes, decoded here once: -1 the
   database could not be opened, -2 the transaction aborted (as it does
   when storage is full), -3 a batch that was malformed (nothing was
   written). *)
#pub datavtype write_failure =
  | WriteNoDatabase                               (* indexedDB.open failed, or the database could not be used *)
  | WriteAborted                                  (* the transaction aborted: nothing of it was kept *)
  | BadBatch                                      (* idb_write_all: the batch was malformed: nothing was written *)
  | WriteUnexpected of (idb_unexpected, int)      (* an answer bridge does not recognise, and its code *)

(* Whether a write (a put or a delete) was kept. JS's answer is decoded
   here, once: 0 is Stored, anything else NotStored with its cause. *)
#pub datavtype stored =
  | Stored
  | NotStored of (write_failure)

(* What a read found. A read that failed is Unreadable, never Absent, so
   a caller cannot take it for an empty value and write a default over
   data it could not see; it carries why. Linear: Found holds a blob JS
   keeps until it is freed, so the one consumer takes it apart with
   case+ ~ and frees the blob; a lookup no consumer takes is freed by
   promise's dispose. *)
#pub datavtype lookup =
  | Found of ([n:nat] dblob(n))
  | Absent                              (* nothing is stored there *)
  | Unreadable of (unreadable_cause)    (* it could not be read *)

#pub fun unreadable_cause_free (cause: unreadable_cause): void

#pub fun write_failure_free (cause: write_failure): void

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

(* Every entry whose key starts with the prefix (an empty prefix: every
   entry), read in ONE readonly transaction, so the entries are one
   consistent view. Found is one blob holding, for each entry in key
   order:
     u16 little-endian key length, the key (UTF-8),
     u32 little-endian value length, the value.
   Absent when there are none. A key longer than 65535 bytes, or a value
   that is not bytes, makes the read Unreadable(ReadFailed). *)
#pub fun idb_get_prefix
  : {lb:agz}{n:nat}
  (!$A.borrow(byte, lb, n), int n) -> $P.promise(lookup, $P.Chained)

(* An atomic batch: ONE readwrite transaction that puts and deletes many
   keys, all or none (the transaction aborts as a whole: WriteAborted).
   The borrowed bytes are a sequence of operations, in order:
     u8 op (1 = put, 2 = delete),
     u16 little-endian key length (not 0), the key (UTF-8),
     and for a put only: u32 little-endian value length, the value.
   A batch that is malformed (a length past the end, an op that is
   neither 1 nor 2, a key that is empty or not UTF-8) writes nothing and
   is NotStored(BadBatch). An empty batch is Stored. *)
#pub fun idb_write_all
  : {lb:agz}{n:nat}
  (!$A.borrow(byte, lb, n), int n) -> $P.promise(stored, $P.Chained)

(* What an update writes, decided from what it read. Write puts the bytes
   under the key that was read. WriteBatch applies a batch in idb_write_all's
   layout (u8 op 1 = put / 2 = delete, u16le key length, key, and for a
   put u32le value length, value) on the same transaction, so what it
   writes (the key read, other keys, or both) is kept together or not at
   all; the key need not appear in it. A malformed batch writes nothing,
   aborts the transaction and answers NotUpdated(BadBatch). Neither writes
   after a read that failed. Linear: Write and WriteBatch hold the bytes, which the bridge frees after handing them to JS (or, when
   nothing may be written, without). *)
#pub datavtype writeback =
  | Keep                                                      (* write nothing *)
  | {l:agz}{n:nat} Write of ($A.arr(byte, l, n), int n)       (* put these bytes under the key *)
  | {l:agz}{n:nat} WriteBatch of ($A.arr(byte, l, n), int n)  (* apply this batch, in the same transaction *)

(* How an update ended. *)
#pub datavtype updated =
  | Updated                                  (* the closure's bytes were put, and the transaction committed *)
  | KeptAsRead                               (* nothing was written (Keep), and the transaction committed *)
  | UpdateUnreadable of (unreadable_cause)   (* the key could not be read: the closure was told, and nothing was written *)
  | NotUpdated of (write_failure)            (* the read was fine and the transaction aborted: nothing was written *)

(* Read, decide and write in ONE readwrite transaction: the closure is
   given what the key holds (Absent, Found, or Unreadable(cause)) while
   the transaction is still active, and answers at once with what to
   write. The value written was decided from the value read in the same
   transaction, so two updates of one key never overwrite each other's
   change: the second reads what the first wrote. The closure runs
   exactly once and is freed, even when the read failed (it is then
   given Unreadable and nothing is written, whatever it answers: a
   record that could not be read is never written over). It is run
   while JS dispatches the read's success, so it must not wait. *)
#pub fun idb_update
  : {lk:agz}{nk:pos}
  (!$A.borrow(byte, lk, nk), int nk,
   (lookup) -<lincloptr1> writeback) -> $P.promise(updated, $P.Chained)

(* A write's promise of JS's code (0, or a negative one when it failed), decoded:
   file.bats's writes to IndexedDB answer as idb_put's do *)
#pub fun stored_decode
  (p: $P.promise(Int, $P.Pending)): $P.promise(stored, $P.Chained)

#pub fun idb_delete_database(): void

#pub fun on_idb_fire
  (resolver_id: int, status: Int): void = "ext#bats_idb_fire"

#pub fun on_idb_fire_get
  (resolver_id: int, handle: Int): void = "ext#bats_idb_fire_get"

(* JS has read the key of an update and its transaction is still active:
   the closure is run now, with the read's code (a blob's handle, 0 for
   nothing there, or a negative code), and the bytes it answers are
   handed back to JS (bats_idb_js_update_write) before this returns *)
#pub fun on_idb_update_apply
  (resolver_id: int, answer: Int): void = "ext#bats_idb_update_apply"

(* The update's transaction ended (0 put, 1 nothing put, or a negative
   code: -1 the database could not be used, -3 the read failed, -2 the
   transaction aborted after a good read, -4 a malformed batch). A closure not yet run is run
   first, with an unreadable lookup, so it is never lost *)
#pub fun on_idb_update_done
  (resolver_id: int, status: Int): void = "ext#bats_idb_update_done"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

(* JS's code for a blob, as a handle: bridge's own atoms are the only
   ones that give one *)
fn _claimed_blob (code: int): $R.option([n:nat] dblob(n)) =
  blob_claim($UNSAFE begin $UNSAFE.cast{blob_handle}(code) end)

$UNSAFE begin
%{
extern void bats_idb_js_put(void*, int, void*, int, int);
extern void bats_idb_js_get(void*, int, int);
extern void bats_idb_js_delete(void*, int, int);
extern void bats_idb_js_list_keys(void*, int, int);
extern void bats_idb_js_get_prefix(void*, int, int);
extern void bats_idb_js_write_all(void*, int, int);
extern void bats_idb_js_update(void*, int, int);
extern void bats_idb_js_update_write(int, void*, int);
extern void bats_idb_js_update_batch(int, void*, int);
extern void bats_js_idb_delete_database(void);

/* The closures of updates JS has not yet read for: slot i is the closure
   of the resolver stashed under id i, taken (and so emptied) when it is
   run, once. The table doubles when an id is past its end. */
static void **_idb_update_table = 0;
static int _idb_update_cap = 0;

void bats_idb_update_hold(int id, void *closure) {
  if (id < 0) return;
  if (id >= _idb_update_cap) {
    int cap = _idb_update_cap ? _idb_update_cap : 16;
    void **grown;
    int i;
    while (cap <= id) cap *= 2;
    grown = (void**)malloc(cap * sizeof(void*));
    for (i = 0; i < cap; i++) grown[i] = i < _idb_update_cap ? _idb_update_table[i] : (void*)0;
    if (_idb_update_table) free(_idb_update_table);
    _idb_update_table = grown;
    _idb_update_cap = cap;
  }
  _idb_update_table[id] = closure;
}

void *bats_idb_update_take(int id) {
  void *closure;
  if (id < 0 || id >= _idb_update_cap) return (void*)0;
  closure = _idb_update_table[id];
  _idb_update_table[id] = (void*)0;
  return closure;
}
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
extern fun _bats_idb_js_get_prefix
  (pfx: ptr, pfx_len: int, resolver_id: int)
  : void = "mac#bats_idb_js_get_prefix"
extern fun _bats_idb_js_write_all
  (batch: ptr, batch_len: int, resolver_id: int)
  : void = "mac#bats_idb_js_write_all"
extern fun _bats_idb_js_update
  (key: ptr, key_len: int, resolver_id: int)
  : void = "mac#bats_idb_js_update"
extern fun _bats_idb_js_update_write
  (resolver_id: int, data: ptr, len: int)
  : void = "mac#bats_idb_js_update_write"
extern fun _bats_idb_js_update_batch
  (resolver_id: int, data: ptr, len: int)
  : void = "mac#bats_idb_js_update_batch"
extern fun _bats_js_idb_delete_database
  (): void = "mac#bats_js_idb_delete_database"
end

(* JS's codes for a write: 0 stored; -1 the database could not be used,
   -2 the transaction aborted, -3 a malformed batch. Any other is not
   one JS gives *)
fn _write_failure (code: Int): write_failure =
  if code = ~1 then WriteNoDatabase()
  else if code = ~2 then WriteAborted()
  else if code = ~3 then BadBatch()
  else WriteUnexpected(UnknownCode(), code)

fn _stored (code: Int): stored =
  if code = 0 then Stored() else NotStored(_write_failure(code))

(* A write's outcome nobody took: nothing to free. ATS2 resolves a
   template's instances in file order, so each dispose comes before its
   first use. *)
implement unreadable_cause_free (cause) =
  case+ cause of
  | ~NoDatabase() => ()
  | ~ReadFailed() => ()
  | ~UnreadableUnexpected(_, _) => ()

implement write_failure_free (cause) =
  case+ cause of
  | ~WriteNoDatabase() => ()
  | ~WriteAborted() => ()
  | ~BadBatch() => ()
  | ~WriteUnexpected(_, _) => ()

implement $P.dispose<stored>(outcome) =
  case+ outcome of
  | ~Stored() => ()
  | ~NotStored(cause) => write_failure_free(cause)

(* The cause of a read JS's code names: -1 the database could not be
   used, -2 the read failed; any other negative is not one JS gives *)
fn _unreadable_cause (code: Int): unreadable_cause =
  if code = ~1 then NoDatabase()
  else if code = ~2 then ReadFailed()
  else UnreadableUnexpected(UnknownCode(), code)

(* JS's code for a blob, as a handle: bridge's own atoms are the only
   ones that give one *)
fn _lookup_of_code (code: Int): lookup =
  if code = 0 then Absent()
  else if code < 0 then Unreadable(_unreadable_cause(code))
  else (case+ _claimed_blob(code) of
    | ~$R.some(blob) => Found(blob)
    | ~$R.none() => Unreadable(UnreadableUnexpected(UnclaimedHandle(), code)))

(* A lookup nobody took: its blob is freed *)
implement $P.dispose<lookup>(found) =
  case+ found of
  | ~Found(blob) => blob_free(blob)
  | ~Absent() => ()
  | ~Unreadable(cause) => unreadable_cause_free(cause)

implement stored_decode(p) =
  $P.and_then<Int><stored>(p, llam (code) => $P.ret<stored>(_stored(code)))

(* A read's promise, decoded *)
fn _lookup_promise (p: $P.promise(Int, $P.Pending)): $P.promise(lookup, $P.Chained) =
  $P.and_then<Int><lookup>(p, llam (code) => $P.ret<lookup>(_lookup_of_code(code)))

(* An update's end, JS's code: 0 put, 1 nothing put, -1 the database
   could not be used and -3 the read failed (nothing was read, so the
   closure was told Unreadable), -2 aborted after a good read *)
fn _updated (code: Int): updated =
  if code = 0 then Updated()
  else if code = 1 then KeptAsRead()
  else if code = ~1 then UpdateUnreadable(NoDatabase())
  else if code = ~3 then UpdateUnreadable(ReadFailed())
  else if code = ~2 then NotUpdated(WriteAborted())
  else if code = ~4 then NotUpdated(BadBatch())
  else NotUpdated(WriteUnexpected(UnknownCode(), code))

implement $P.dispose<updated>(outcome) =
  case+ outcome of
  | ~Updated() => ()
  | ~KeptAsRead() => ()
  | ~UpdateUnreadable(cause) => unreadable_cause_free(cause)
  | ~NotUpdated(cause) => write_failure_free(cause)

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

implement idb_get_prefix{lb}{n}(pfx, pfx_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_idb_js_get_prefix(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(pfx) end, pfx_len,
    id)
in _lookup_promise(p) end

implement idb_write_all{lb}{n}(batch, batch_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_idb_js_write_all(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(batch) end, batch_len,
    id)
in stored_decode(p) end

(* Whether a lookup holds a value to decide from: only one read may be
   written over *)
fn _readable (found: !lookup): bool =
  case+ found of
  | Found(_) => true
  | Absent() => true
  | Unreadable(_) => false

(* Runs the closure held under the id, once, with the read's code: what it
   answers is handed to JS (while the transaction is active) when may_write
   and the read was good, and freed either way; the closure is freed *)
fn _update_run (id: int, code: Int, may_write: bool): void = let
  val held = $UNSAFE begin $extfcall(ptr, "bats_idb_update_take", id) end
in
  if ptr_isnot_null(held) then let
    val decide = $UNSAFE begin
      $UNSAFE.castvwtp0{(lookup) -<lincloptr1> writeback}(held) end
    val answer = _lookup_of_code(code)
    val readable = _readable(answer)
    val answered = decide(answer)
    val () = cloptr_free($UNSAFE begin $UNSAFE.castvwtp0{cloptr(void)}(decide) end)
  in
    case+ answered of
    | ~Keep() => ()
    | ~Write(data, len) => let
        val () = if may_write then
          (if readable then _bats_idb_js_update_write(id,
             $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end, len))
      in $A.free<byte>(data) end
    | ~WriteBatch(data, len) => let
        val () = if may_write then
          (if readable then _bats_idb_js_update_batch(id,
             $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end, len))
      in $A.free<byte>(data) end
  end
  else ()
end

implement idb_update{lk}{nk}(key, key_len, decide) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = $UNSAFE begin
    $extfcall(void, "bats_idb_update_hold", id, $UNSAFE.castvwtp0{ptr}(decide)) end
  val () = _bats_idb_js_update(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    id)
in $P.and_then<Int><updated>(p, llam (code) => $P.ret<updated>(_updated(code))) end

implement on_idb_update_apply(resolver_id, answer) =
  _update_run(resolver_id, answer, true)

(* A closure still held was never given the read (the database did not
   open, or the transaction aborted first): it is run now, told the read
   failed, with nothing to write, and then the update's promise settles *)
implement on_idb_update_done(resolver_id, status) = let
  val () = _update_run(resolver_id, (if status = ~1 then ~1 else ~2), false)
in $P.fire(resolver_id, status) end

implement on_idb_fire(resolver_id, status) =
  $P.fire(resolver_id, status)

implement on_idb_fire_get(resolver_id, handle) =
  $P.fire(resolver_id, handle)

implement idb_delete_database() = _bats_js_idb_delete_database()

end (* #target wasm *)
