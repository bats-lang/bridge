(* storage -- keeping what the app stores for bridge *)

#include "share/atspre_staload.hats"

#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

(* Whether the app's storage is kept. JS's answer is decoded here, once:
   anything but its yes is NotPersisted. *)
#pub datatype persist_outcome =
  | Persisted     (* kept: already, or granted now; always in the app *)
  | NotPersisted  (* not kept: refused, or not available *)

(* Whether the app's storage can be made persistent (kept when the
   device runs short, not evicted). Browser: navigator.storage.persist.
   App (Capacitor): always, as its storage is the app's own. *)
#pub fun storage_available(): bool

(* Asks that the app's storage be kept: the promise resolves with
   whether it is. A browser may grant it only once the app
   is used (after a file is stored, say), or installed. *)
#pub fun storage_persist(): $P.promise(persist_outcome, $P.Chained)

(* Whether the app's storage is kept, without asking *)
#pub fun storage_persisted(): $P.promise(persist_outcome, $P.Chained)

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern int bats_js_storage_available(void);
extern void bats_js_storage_ask(int, int);
%}
extern fun _bats_js_storage_available
  (): int = "mac#bats_js_storage_available"
extern fun _bats_js_storage_ask
  (persist: int, resolver_id: int): void = "mac#bats_js_storage_ask"
end

(* JS's codes: 1 kept, 0 not *)
fn _persist_outcome (code: Int): persist_outcome =
  if code = 1 then Persisted() else NotPersisted()

fn _storage_ask (persist: int): $P.promise(persist_outcome, $P.Chained) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_storage_ask(persist, id)
in $P.and_then<Int><persist_outcome>(p, lam (code) =>
  $P.ret<persist_outcome>(_persist_outcome(code))) end

implement storage_available() = _bats_js_storage_available() > 0

implement storage_persist() = _storage_ask(1)

implement storage_persisted() = _storage_ask(0)

end (* #target wasm *)
