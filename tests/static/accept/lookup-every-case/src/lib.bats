#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload ID = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"

(* Reads matched in every case, their blob and file freed; a write's
   outcome matched; a lookup let go is freed by its dispose *)
fn f (): void = let
  val key = $A.alloc<byte>(3)
  val () = $A.write_text(key, 0, $A.text_lit("lib"), 3)
  val @(frozen, borrowed) = $A.freeze<byte>(key)
  val () = $P.finish<$ID.lookup>($ID.idb_get(borrowed, 3), llam (found) =>
    case+ found of
    | ~$ID.Found(blob) => $DC.blob_free(blob)
    | ~$ID.Absent() => ()
    | ~$ID.Unreadable(cause) => $ID.unreadable_cause_free(cause))
  val () = $P.finish<$BF.file_lookup>($BF.file_idb_get(borrowed, 3), llam (found) =>
    case+ found of
    | ~$BF.FileFound(f) => $BF.file_close(f)
    | ~$BF.FileAbsent() => ()
    | ~$BF.FileUnreadable() => ())
  val value = $A.dup<byte>(frozen, borrowed)
  val () = $P.finish<$ID.stored>($ID.idb_put(borrowed, 3, value, 3), llam (outcome) =>
    case+ outcome of
    | $ID.Stored() => ()
    | $ID.NotStored() => ())
  val () = $A.drop<byte>(frozen, value)
  val () = $P.discard<$ID.lookup>($ID.idb_list_keys(borrowed, 3))
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end
