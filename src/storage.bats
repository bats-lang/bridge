(* storage -- keeping what the app stores for bridge *)

#include "share/atspre_staload.hats"

#use promise as P
#use result as R
staload "./decompress.bats"

(* ============================================================
   Public API
   ============================================================ *)

(* Whether the app's storage is kept. JS's answer is decoded here, once:
   anything but its yes is NotPersisted. Deprecated (storage, bridge#227):
   it folds a rejection and an answer that is no boolean into NotPersisted;
   persist_answer tells them apart. *)
#pub datatype persist_outcome =
  | Persisted     (* kept: already, or granted now; always in the app *)
  | NotPersisted  (* not kept: refused, or not available *)

(* Whether the app's storage is kept, each outcome its own. JS's answer is
   decoded here, once: the platform's yes and no, the call rejected or
   thrown (its error as text, none when JS could not write it down), an
   answer that is no boolean (as text), and a code JS never gives. Linear
   (the text), so the one consumer takes it apart with case+ ~; one no
   consumer takes is freed by promise's dispose. *)
#pub datavtype persist_answer =
  | PersistKept                                                  (* kept: already, or granted now; always in the app *)
  | PersistNotKept                                               (* the platform answered false *)
  | PersistRefused of $R.option([n:nat] dblob(n))                (* the call was rejected or threw: what, as text *)
  | PersistAnswerOdd of $R.option([n:nat] dblob(n))              (* the platform answered something that is no boolean: as text *)
  | PersistUnexpected of Int                                     (* a code JS never gives *)

(* Whether the app's storage can be made persistent (kept when the
   device runs short, not evicted). Browser: navigator.storage.persist.
   App (Capacitor): always, as its storage is the app's own. *)
#pub fun storage_available(): bool

(* Asks that the app's storage be kept: the promise resolves with
   whether it is. A browser may grant it only once the app
   is used (after a file is stored, say), or installed. Deprecated
   (storage, bridge#227): storage_persist_answer. *)
#pub fun storage_persist(): $P.promise(persist_outcome, $P.Chained)

(* Whether the app's storage is kept, without asking. Deprecated
   (storage, bridge#227): storage_persisted_answer. *)
#pub fun storage_persisted(): $P.promise(persist_outcome, $P.Chained)

(* storage_persist with every outcome its own *)
#pub fun storage_persist_answer(): $P.promise(persist_answer, $P.Chained)

(* storage_persisted with every outcome its own *)
#pub fun storage_persisted_answer(): $P.promise(persist_answer, $P.Chained)

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern int bats_js_storage_available(void);
extern void bats_js_storage_ask(int, int);
extern int bats_js_storage_text(int);
%}
extern fun _bats_js_storage_available
  (): int = "mac#bats_js_storage_available"
extern fun _bats_js_storage_ask
  (persist: int, resolver_id: int): void = "mac#bats_js_storage_ask"
extern fun _bats_js_storage_text
  (resolver_id: int): int = "mac#bats_js_storage_text"
end

(* What a call rejected with or answered, as text: JS kept it under the
   call's number, and none when it could not be written down *)
fn _storage_text (resolver_id: int): $R.option([n:nat] dblob(n)) = let
  val handle = _bats_js_storage_text(resolver_id)
in
  if handle <= 0 then $R.none()
  else blob_claim($UNSAFE begin $UNSAFE.cast{blob_handle}(handle) end)
end

(* JS's codes: 1 kept, 0 not kept, -3 rejected or threw, -4 an answer that
   is no boolean (the text of -3 and -4 kept by the call's number); any
   other is a code JS never gives *)
fn _persist_answer (code: Int, resolver_id: int): persist_answer =
  if code = 1 then PersistKept()
  else if code = 0 then PersistNotKept()
  else if code = ~3 then PersistRefused(_storage_text(resolver_id))
  else if code = ~4 then PersistAnswerOdd(_storage_text(resolver_id))
  else PersistUnexpected(code)

fn _free_text (text: $R.option([n:nat] dblob(n))): void =
  case+ text of ~$R.some(blob) => blob_free(blob) | ~$R.none() => ()

(* An answer nobody took: its text freed *)
implement $P.dispose<persist_answer>(answer) =
  case+ answer of
  | ~PersistKept() => ()
  | ~PersistNotKept() => ()
  | ~PersistRefused(text) => _free_text(text)
  | ~PersistAnswerOdd(text) => _free_text(text)
  | ~PersistUnexpected(_) => ()

(* An outcome nobody took: nothing to free *)
implement $P.dispose<persist_outcome>(_) = ()

fn _storage_ask (persist: int): $P.promise(persist_answer, $P.Chained) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_storage_ask(persist, id)
in $P.and_then<Int><persist_answer>(p, llam (code) =>
  $P.ret<persist_answer>(_persist_answer(code, id))) end

(* The old outcome (storage): equal to the old JS for every answer the platform
   documents (StorageManager.persist/persisted: a Promise of a boolean): true
   is Persisted, false NotPersisted; a rejection and a throw NotPersisted. It
   differs only for an answer the platform never gives, a truthy non-boolean
   (the old JS wrote `v ? 1 : 0`, so 'yes' was Persisted; now NotPersisted):
   JS decides nothing, so the truthiness stays out of it (the text freed) *)
fn _persist_outcome (answer: persist_answer): persist_outcome =
  case+ answer of
  | ~PersistKept() => Persisted()
  | ~PersistNotKept() => NotPersisted()
  | ~PersistRefused(text) => let val () = _free_text(text) in NotPersisted() end
  | ~PersistAnswerOdd(text) => let val () = _free_text(text) in NotPersisted() end
  | ~PersistUnexpected(_) => NotPersisted()

fn _storage_ask_outcome (persist: int): $P.promise(persist_outcome, $P.Chained) =
  $P.and_then<persist_answer><persist_outcome>(_storage_ask(persist), llam (answer) =>
    $P.ret<persist_outcome>(_persist_outcome(answer)))

implement storage_available() = _bats_js_storage_available() > 0

implement storage_persist() = _storage_ask_outcome(1)

implement storage_persisted() = _storage_ask_outcome(0)

implement storage_persist_answer() = _storage_ask(1)

implement storage_persisted_answer() = _storage_ask(0)

end (* #target wasm *)
