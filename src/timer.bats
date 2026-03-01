(* timer -- timer and exit for bridge *)

#include "share/atspre_staload.hats"

#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

#pub fun timer_set
  (delay_ms: int): $P.promise(int, $P.Pending)

#pub fun get_time_ms(): int

#pub fun exit(): void

#pub fun on_timer_fire
  (resolver_id: int): void = "ext#bats_timer_fire"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin

extern fun _bats_set_timer
  (delay_ms: int, resolver_id: int): void = "mac#bats_set_timer"
extern fun _bats_get_time_ms
  (): int = "mac#bats_get_time_ms"
extern fun _bats_exit
  (): void = "mac#bats_exit"

implement timer_set(delay_ms) = let
  val @(p, r) = $P.create<int>()
  val id = $P.stash(r)
  val () = _bats_set_timer(delay_ms, id)
in p end

implement get_time_ms() = _bats_get_time_ms()

implement exit() = _bats_exit()

implement on_timer_fire(resolver_id) =
  $P.fire(resolver_id, 0)

end (* $UNSAFE *)
end (* #target wasm *)
