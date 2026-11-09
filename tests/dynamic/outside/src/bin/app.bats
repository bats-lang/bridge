#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use wasm.bats-packages.dev/bridge as B
staload OU = "wasm.bats-packages.dev/bridge/src/outside.bats"
staload ID = "wasm.bats-packages.dev/bridge/src/idb.bats"
staload WI = "wasm.bats-packages.dev/bridge/src/window.bats"

(* Outside reads: a GET answers only for an http(s) URL (before the fetch and
   after redirects), and a body held outside goes into the second IndexedDB
   database and comes back from it: put, get, delete, get again. Each step logs
   one line *)

fn exact {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

fn lit {n:pos | n < 256} (s: string n): [l:agz] @($A.frozen(byte, l, n, 1), $A.borrow(byte, l, n)) =
  $A.freeze<byte>(exact(s))

fn rel {l:agz}{n:nat} (fz: $A.frozen(byte, l, n, 1), b: $A.borrow(byte, l, n)): void = let
  val () = $A.drop<byte>(fz, b)
in $A.free<byte>($A.thaw<byte>(fz)) end

fn say {n:pos | n < 256} (line: string n): void = let
  val @(fz, b) = lit(line)
  val () = $WI.log($WI.Info(), b, g1u2i(string1_length(line)))
in rel(fz, b) end

(* The key under which the body is kept *)
fn key_get {k:pos | k < 256} (key: string k): void = let
  val @(kz, kb) = lit(key)
  val p = $OU.file_idb_get_outside(kb, g1u2i(string1_length(key)))
  val () = rel(kz, kb)
in $P.finish<$OU.file_lookup_outside>(p, llam (got) =>
  case+ got of
  | ~$OU.FoundOutside(f) => let
      val n = $OU.file_size_outside(f)
      val () = (if n = 5 then say("get: found, 5 bytes") else say("get: found, other size"))
    in $OU.file_close_outside(f) end
  | ~$OU.NotFoundOutside() => say("get: nothing there")
  | ~$OU.LookupFailedOutside() => say("get: failed")) end

fn put_then {l:agz}{n:pos}{cs:$A.cells}
  (pf: $OU.OUTSIDE_READ(cs) | cb: !$A.cborrow(l, n, cs), n: int n): void = let
  val f = $OU.file_store_outside(pf | cb, n)
  val @(kz, kb) = lit("k1")
  val p = $OU.file_idb_put_outside(kb, 2, f)
  val () = rel(kz, kb)
  val () = $OU.file_close_outside(f)
in $P.finish<$ID.stored>(p, llam (st) => let
  val () = (case+ st of
    | $ID.Stored() => say("put: stored")
    | $ID.NotStored() => say("put: not stored"))
  val () = key_get("k1")
  val @(dz, db) = lit("k1")
  val d = $OU.file_idb_delete_outside(db, 2)
  val () = rel(dz, db)
in $P.finish<$ID.stored>(d, llam (st2) => let
  val () = (case+ st2 of
    | $ID.Stored() => say("delete: stored")
    | $ID.NotStored() => say("delete: not stored"))
  val () = key_get("k1")
in key_get("never") end) end) end

fn keep {m:pos | m <= 1048576} (b: !$OU.dblob_outside(m), m: int m): void = let
  val a = $A.alloc<byte>(m)
  val @(pfo, pfc, pflent | ba) = $OU.blob_read_outside(b, a, m)
  val @(fz, cb) = $A.barr_freeze(ba)
  val () = put_then(pfo | cb, m)
  val () = $A.cborrow_drop(fz, cb)
  val back = $A.barr_to_arrx(pflent | $A.barr_thaw(fz))
in $A.free<byte>(back) end

fn handle {k:nat} (b: $OU.dblob_outside(k)): void = let
  val m = $OU.blob_len_outside(b)
  val () = (if m > 0 then (if m <= 1048576 then keep(b, m) else ()) else ())
in $OU.blob_free_outside(b) end

fn fetch_line {n,a,c:pos | n < 256; a < 256; c < 256} (url: string n, ok: string a, none: string c): void = let
  val @(uz, ub) = lit(url)
  val p = $OU.fetch_outside(ub, g1u2i(string1_length(url)))
  val () = rel(uz, ub)
in $P.finish<$OU.fetched_outside>(p, llam (got) =>
  case+ got of
  | ~$OU.FetchedOutside(b) => let
      val () = say(ok)
    in handle(b) end
  | ~$OU.NotFetchedOutside() => say(none)) end

implement main0 () = let
  val () = fetch_line("javascript:go()", "fetch javascript: body", "fetch javascript: none")
  val () = fetch_line("data:text/plain,hello", "fetch data: body", "fetch data: none")
  val () = fetch_line("http://localhost/to-data", "fetch redirect to data: body", "fetch redirect to data: none")
  val () = fetch_line("http://localhost/no-url", "fetch with no final url body", "fetch with no final url none")
  val () = fetch_line("http://localhost/refused", "fetch refused body", "fetch refused none")
in fetch_line("http://localhost/hello", "fetch http: body", "fetch http: none") end
