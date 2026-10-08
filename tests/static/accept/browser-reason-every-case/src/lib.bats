#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload ID = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A cause matched in every case, down to what the browser said, each
   one free of what it holds: the blob of a name bridge does not
   recognise is freed, and where the read failed (the database, or the
   request) is kept apart from why *)
fn reason_said (reason: $ID.browser_reason): int =
  case+ reason of
  | ~$ID.Transient() => 1
  | ~$ID.StorageBlocked() => 2
  | ~$ID.NewerVersion() => 3
  | ~$ID.Aborted() => 4
  | ~$ID.NoErrorGiven() => 0
  | ~$ID.BrowserUnexpected(blob) => let val () = $DC.blob_free(blob) in 5 end

fn cause_said (cause: $ID.unreadable_cause): int =
  case+ cause of
  | ~$ID.NoDatabase(reason) => reason_said(reason)
  | ~$ID.ReadFailed(reason) => 10 + reason_said(reason)
  | ~$ID.UnreadableUnexpected(which, _) => (case+ which of
    | $ID.UnknownCode() => 20
    | $ID.UnclaimedHandle() => 21)

(* An update's cause is the same type *)
fn updated_said (outcome: $ID.updated): int =
  case+ outcome of
  | ~$ID.Updated() => 0
  | ~$ID.KeptAsRead() => 0
  | ~$ID.UpdateUnreadable(cause) => cause_said(cause)
  | ~$ID.NotUpdated(cause) => let val () = $ID.write_failure_free(cause) in 0 end
