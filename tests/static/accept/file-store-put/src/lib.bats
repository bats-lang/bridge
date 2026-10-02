#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"
staload ID = "wasm.bats-packages.dev/bridge/src/idb.sats"

(* A stored file is kept in IndexedDB, read back, then closed *)
fn f {l:agz}{n:pos} (data: !$A.borrow(byte, l, n), len: int n,
    key: !$A.borrow(byte, l, n)): $P.promise($ID.stored, $P.Chained) = let
  val fl = $BF.file_store(data, len)
  val p = $BF.file_idb_put(key, len, fl)
  val buf = $A.alloc<byte>(1)
  val () = $BF.file_read(fl, 0, buf, 1)
  val () = $A.free<byte>(buf)
  val () = $BF.file_close(fl)
in p end
