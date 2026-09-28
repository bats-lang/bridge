(* timer -- timer and exit for bridge *)

#include "share/atspre_staload.hats"

#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

#pub fun timer_set
  : (int) -> $P.promise_pending(Int)

(* Whole minutes since the Unix epoch, by the host's clock: JS's word, a
   host value for the caller to check (a clock can be set before 1970) *)
#pub fun epoch_minutes(): [v:int] int v

#pub fun exit(): void

#pub fun on_timer_fire
  (resolver_id: int): void = "ext#bats_timer_fire"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_set_timer(int, int);
extern int bats_js_epoch_minutes(void);
extern void bats_exit(void);
%}
extern fun _bats_set_timer
  (delay_ms: int, resolver_id: int): void = "mac#bats_set_timer"
extern fun _bats_js_epoch_minutes
  (): [v:int] int v = "mac#bats_js_epoch_minutes"
extern fun _bats_exit
  (): void = "mac#bats_exit"
end

implement timer_set(delay_ms) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_set_timer(delay_ms, id)
in p end

implement epoch_minutes() = _bats_js_epoch_minutes()

implement exit() = _bats_exit()

implement on_timer_fire(resolver_id) =
  $P.fire(resolver_id, 0)

end (* #target wasm *)
