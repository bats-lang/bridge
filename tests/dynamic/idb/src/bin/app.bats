#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload ID = "wasm.bats-packages.dev/bridge/src/idb.bats"
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.bats"

(* Drives bridge's IndexedDB atoms from a script check.mjs hands over.
   check.mjs calls test_run, which asks for the script (test_script), runs
   every command of it at once (so the transactions are started in one
   tick), and reports each outcome (test_report: the command's number, a
   tag saying which constructor, a number, and bytes). The script is a
   sequence of commands: a u8 command, a u16le length and bytes (the key),
   a u32le length and bytes (the data).

   Commands: 1 put key data; 2 get key; 3 delete key; 4 list keys with the
   prefix key; 5 get everything under the prefix key; 6 write_all the batch
   data; 7 update key by adding 1 to the counter it holds (4 bytes,
   little-endian; absent is 0; unreadable is kept); 8 update key keeping
   what it holds; 9 update key to put data, whatever it holds; 10 update key
   to apply the batch data, whatever it holds. A closure
   of an update reports what it was given too, as its tag + 100.

   Tags: lookups 0 absent, 1 found, 2 no database, 3 read failed,
   4 unknown code, 5 unclaimed handle; writes 10 stored, 11 no database,
   12 aborted, 13 bad batch, 14 unknown code; updates 20 updated, 21 kept
   as read, 22 unreadable (no database), 23 unreadable (read failed),
   24 unreadable (unknown code), 25 unreadable (unclaimed handle),
   26 not updated (no database), 27 not updated (aborted), 28 not updated
   (bad batch), 29 not updated (unknown code) *)

$UNSAFE begin
%{
extern int test_script(void*, int);
extern void test_report(int, int, int, void*, int);
%}
extern fun _test_script
  (out: ptr, cap: int): int = "mac#test_script"
extern fun _test_report
  (index: int, tag: int, number: int, data: ptr, len: int): void = "mac#test_report"
end

#define SCRIPT_MAX 65536

(* A script's bytes, kept: a closure reads its data from here when it runs *)
val the_script = ref<ptr>(the_null_ptr)

fn u8_at (p: ptr, i: int): int =
  byte2int0($UNSAFE begin $UNSAFE.ptr0_get<byte>(ptr_add<byte>(p, i)) end)

fn u16_at (p: ptr, i: int): int = u8_at(p, i) + 256 * u8_at(p, i + 1)

fn u32_at (p: ptr, i: int): int = u16_at(p, i) + 65536 * u16_at(p, i + 2)

fun fill {l:agz}{n:pos}{i:nat | i <= n} .<n - i>.
  (a: !$A.arr(byte, l, n), from: ptr, n: int n, i: int i): void =
  if i >= n then ()
  else let
    val () = $A.set<byte>(a, i, $UNSAFE begin $UNSAFE.ptr0_get<byte>(ptr_add<byte>(from, i)) end)
  in fill(a, from, n, i + 1) end

(* A copy of n bytes at from *)
fn slice {n:pos | n <= 1048576} (from: ptr, n: int n): [l:agz] $A.arr(byte, l, n) = let
  val a = $A.alloc<byte>(n)
  val () = fill(a, from, n, 0)
in a end

(* n as a length of a buffer: the caller has checked 0 < n <= 1 MiB *)
fn as_length (n: int): [m:pos | m <= 1048576] int m =
  $UNSAFE begin $UNSAFE.cast{[m:pos | m <= 1048576] int m}(n) end

fn report (index: int, tag: int, number: int): void =
  _test_report(index, tag, number, the_null_ptr, 0)

(* The blob's bytes are reported with the tag; the blob is freed *)
fn report_blob (index: int, tag: int, blob: [n:nat] $DC.dblob(n)): void = let
  val n = $DC.blob_len(blob)
in
  if n > 0 then
    (if n <= 1048576 then let
       val a = $A.alloc<byte>(n)
       val () = $DC.blob_read(blob, 0, a, n)
       val () = _test_report(index, tag, n,
         $UNSAFE begin $UNSAFE.castvwtp1{ptr}(a) end, n)
       val () = $A.free<byte>(a)
     in $DC.blob_free(blob) end
     else let val () = report(index, tag, ~1) in $DC.blob_free(blob) end)
  else let val () = report(index, tag, 0) in $DC.blob_free(blob) end
end

(* base is 0, or 100 for what an update's closure was given *)
fn report_lookup (index: int, base: int, found: $ID.lookup): void =
  case+ found of
  | ~$ID.Found(blob) => report_blob(index, base + 1, blob)
  | ~$ID.Absent() => report(index, base + 0, 0)
  | ~$ID.Unreadable(cause) => (case+ cause of
    | ~$ID.NoDatabase() => report(index, base + 2, 0)
    | ~$ID.ReadFailed() => report(index, base + 3, 0)
    | ~$ID.UnreadableUnexpected(which, code) => (case+ which of
      | $ID.UnknownCode() => report(index, base + 4, code)
      | $ID.UnclaimedHandle() => report(index, base + 5, code)))

fn report_stored (index: int, outcome: $ID.stored): void =
  case+ outcome of
  | ~$ID.Stored() => report(index, 10, 0)
  | ~$ID.NotStored(cause) => (case+ cause of
    | ~$ID.WriteNoDatabase() => report(index, 11, 0)
    | ~$ID.WriteAborted() => report(index, 12, 0)
    | ~$ID.BadBatch() => report(index, 13, 0)
    | ~$ID.WriteUnexpected(_, code) => report(index, 14, code))

fn report_updated (index: int, outcome: $ID.updated): void =
  case+ outcome of
  | ~$ID.Updated() => report(index, 20, 0)
  | ~$ID.KeptAsRead() => report(index, 21, 0)
  | ~$ID.UpdateUnreadable(cause) => (case+ cause of
    | ~$ID.NoDatabase() => report(index, 22, 0)
    | ~$ID.ReadFailed() => report(index, 23, 0)
    | ~$ID.UnreadableUnexpected(which, code) => (case+ which of
      | $ID.UnknownCode() => report(index, 24, code)
      | $ID.UnclaimedHandle() => report(index, 25, code)))
  | ~$ID.NotUpdated(cause) => (case+ cause of
    | ~$ID.WriteNoDatabase() => report(index, 26, 0)
    | ~$ID.WriteAborted() => report(index, 27, 0)
    | ~$ID.BadBatch() => report(index, 28, 0)
    | ~$ID.WriteUnexpected(_, code) => report(index, 29, code))

(* The counter a lookup holds: 4 bytes little-endian; 0 when absent or not
   4 bytes. The lookup is consumed *)
fn counter_of (found: $ID.lookup): int =
  case+ found of
  | ~$ID.Found(blob) => let
      val n = $DC.blob_len(blob)
    in
      if n = 4 then let
        val a = $A.alloc<byte>(4)
        val () = $DC.blob_read(blob, 0, a, 4)
        val value = byte2int0($A.get<byte>(a, 0)) + 256 * byte2int0($A.get<byte>(a, 1))
          + 65536 * byte2int0($A.get<byte>(a, 2)) + 16777216 * byte2int0($A.get<byte>(a, 3))
        val () = $A.free<byte>(a)
        val () = $DC.blob_free(blob)
      in value end
      else let val () = $DC.blob_free(blob) in 0 end
    end
  | ~$ID.Absent() => 0
  | ~$ID.Unreadable(cause) => let val () = $ID.unreadable_cause_free(cause) in 0 end

fn is_readable (found: !$ID.lookup): bool =
  case+ found of
  | $ID.Found(_) => true
  | $ID.Absent() => true
  | $ID.Unreadable(_) => false

fn increment (found: $ID.lookup): $ID.writeback = let
  val readable = is_readable(found)
  val next = counter_of(found) + 1
in
  if readable then let
    val a = $A.alloc<byte>(4)
    val () = $A.set<byte>(a, 0, int2byte0(next % 256))
    val () = $A.set<byte>(a, 1, int2byte0((next / 256) % 256))
    val () = $A.set<byte>(a, 2, int2byte0((next / 65536) % 256))
    val () = $A.set<byte>(a, 3, int2byte0((next / 16777216) % 256))
  in $ID.Write(a, 4) end
  else $ID.Keep()
end

(* The bytes at from, as a write, or Keep when there are none *)
fn written_batch (from: ptr, len: int): $ID.writeback =
  if len > 0 && len <= 1048576 then let
    val n = as_length(len)
  in $ID.WriteBatch(slice(from, n), n) end
  else $ID.Keep()

fn written (from: ptr, len: int): $ID.writeback =
  if len > 0 && len <= 1048576 then let
    val n = as_length(len)
  in $ID.Write(slice(from, n), n) end
  else $ID.Keep()

(* A command: its key (or, for write_all, its data) is copied, lent to
   the call, and freed when the call has returned: the bridge reads it
   before it returns *)
fn run_command (index: int, command: int, script: ptr, key_at: int, key_len: int,
                data_at: int, data_len: int): void =
  if command = 6 then
    (if data_len > 0 && data_len <= 1048576 then let
       val n = as_length(data_len)
       val @(frozen, batch) = $A.freeze<byte>(slice(ptr_add<byte>(script, data_at), n))
       val promise = $ID.idb_write_all(batch, n)
       val () = $A.drop<byte>(frozen, batch)
       val () = $A.free<byte>($A.thaw<byte>(frozen))
     in $P.finish<$ID.stored>(promise, llam (outcome) => report_stored(index, outcome)) end
     else ())
  else if key_len > 0 && key_len <= 1048576 then let
    val n = as_length(key_len)
    val @(frozen, key) = $A.freeze<byte>(slice(ptr_add<byte>(script, key_at), n))
  in
    if command = 1 then
      (if data_len > 0 && data_len <= 1048576 then let
         val m = as_length(data_len)
         val @(data_frozen, data) = $A.freeze<byte>(slice(ptr_add<byte>(script, data_at), m))
         val promise = $ID.idb_put(key, n, data, m)
         val () = $A.drop<byte>(data_frozen, data)
         val () = $A.free<byte>($A.thaw<byte>(data_frozen))
         val () = $A.drop<byte>(frozen, key)
         val () = $A.free<byte>($A.thaw<byte>(frozen))
       in $P.finish<$ID.stored>(promise, llam (outcome) => report_stored(index, outcome)) end
       else let
         val () = $A.drop<byte>(frozen, key)
       in $A.free<byte>($A.thaw<byte>(frozen)) end)
    else if command = 2 then let
      val promise = $ID.idb_get(key, n)
      val () = $A.drop<byte>(frozen, key)
      val () = $A.free<byte>($A.thaw<byte>(frozen))
    in $P.finish<$ID.lookup>(promise, llam (found) => report_lookup(index, 0, found)) end
    else if command = 3 then let
      val promise = $ID.idb_delete(key, n)
      val () = $A.drop<byte>(frozen, key)
      val () = $A.free<byte>($A.thaw<byte>(frozen))
    in $P.finish<$ID.stored>(promise, llam (outcome) => report_stored(index, outcome)) end
    else if command = 4 then let
      val promise = $ID.idb_list_keys(key, n)
      val () = $A.drop<byte>(frozen, key)
      val () = $A.free<byte>($A.thaw<byte>(frozen))
    in $P.finish<$ID.lookup>(promise, llam (found) => report_lookup(index, 0, found)) end
    else if command = 5 then let
      val promise = $ID.idb_get_prefix(key, n)
      val () = $A.drop<byte>(frozen, key)
      val () = $A.free<byte>($A.thaw<byte>(frozen))
    in $P.finish<$ID.lookup>(promise, llam (found) => report_lookup(index, 0, found)) end
    else if command = 7 then let
      val promise = $ID.idb_update(key, n, llam (found) => increment(found))
      val () = $A.drop<byte>(frozen, key)
      val () = $A.free<byte>($A.thaw<byte>(frozen))
    in $P.finish<$ID.updated>(promise, llam (outcome) => report_updated(index, outcome)) end
    else if command = 8 then let
      val promise = $ID.idb_update(key, n, llam (found) => let
        val () = report_lookup(index, 100, found)
      in $ID.Keep() end)
      val () = $A.drop<byte>(frozen, key)
      val () = $A.free<byte>($A.thaw<byte>(frozen))
    in $P.finish<$ID.updated>(promise, llam (outcome) => report_updated(index, outcome)) end
    else if command = 10 then let
      val promise = $ID.idb_update(key, n, llam (found) => let
        val () = report_lookup(index, 100, found)
      in written_batch(ptr_add<byte>(!the_script, data_at), data_len) end)
      val () = $A.drop<byte>(frozen, key)
      val () = $A.free<byte>($A.thaw<byte>(frozen))
    in $P.finish<$ID.updated>(promise, llam (outcome) => report_updated(index, outcome)) end
    else let
      val promise = $ID.idb_update(key, n, llam (found) => let
        val () = report_lookup(index, 100, found)
      in written(ptr_add<byte>(!the_script, data_at), data_len) end)
      val () = $A.drop<byte>(frozen, key)
      val () = $A.free<byte>($A.thaw<byte>(frozen))
    in $P.finish<$ID.updated>(promise, llam (outcome) => report_updated(index, outcome)) end
  end
  else ()

fun run_from {fuel:nat} .<fuel>.
  (script: ptr, length: int, at: int, index: int, fuel: int fuel): void =
  if fuel <= 0 then ()
  else if at + 3 > length then ()
  else let
    val command = u8_at(script, at)
    val key_len = u16_at(script, at + 1)
    val key_at = at + 3
    val data_len_at = key_at + key_len
  in
    if data_len_at + 4 > length then ()
    else let
      val data_len = u32_at(script, data_len_at)
      val data_at = data_len_at + 4
      val () = run_command(index, command, script, key_at, key_len, data_at, data_len)
    in run_from(script, length, data_at + data_len, index + 1, fuel - 1) end
  end

#pub fun test_run (): void = "ext#test_run"

implement test_run () = let
  val buffer = $A.alloc<byte>(SCRIPT_MAX)
  val script = $UNSAFE begin $UNSAFE.castvwtp1{ptr}(buffer) end
  val length = _test_script(script, SCRIPT_MAX)
  val () = !the_script := script
  (* the buffer is kept: closures of the commands read their data from it *)
  val leaked = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(buffer) end
in run_from(script, length, 0, 0, 100000) end

implement main0 () = ()
