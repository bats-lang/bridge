(* storage -- keeping what the app stores for bridge *)

#include "share/atspre_staload.hats"

#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

(* Whether the app's storage can be made persistent (kept when the
   device runs short, not evicted). Browser: navigator.storage.persist.
   App (Capacitor): always, as its storage is the app's own. *)
#pub fun storage_available(): bool

(* Asks that the app's storage be kept: the promise resolves with 1 when
   it is (already, or granted now; always in the app), 0 when it is not
   (refused, or not available). A browser may grant it only once the app
   is used (after a file is stored, say), or installed. *)
#pub fun storage_persist(): $P.promise_pending(Int)

(* Whether the app's storage is kept, without asking: 1 or 0, as
   storage_persist's *)
#pub fun storage_persisted(): $P.promise_pending(Int)

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

implement storage_available() = _bats_js_storage_available() > 0

implement storage_persist() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_storage_ask(1, id)
in p end

implement storage_persisted() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_storage_ask(0, id)
in p end

end (* #target wasm *)
