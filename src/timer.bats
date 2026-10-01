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

(* Milliseconds since the Unix epoch (Date.now()), as high * 2^30 + low:
   two ints that stay 32-bit. A clock set before 1970 reads as 0. *)
#pub fun epoch_millis (): @([h:nat] int h, [l:nat | l < 1073741824] int l)

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
extern void bats_js_epoch_millis(void*);
/* Date.now() as its high and low parts, written by JS at one reading */
static int bats_epoch_millis_parts[2];
static int bats_epoch_millis_high(void) {
  bats_js_epoch_millis(bats_epoch_millis_parts);
  return bats_epoch_millis_parts[0];
}
static int bats_epoch_millis_low(void) { return bats_epoch_millis_parts[1]; }
extern void bats_exit(void);
%}
extern fun _bats_set_timer
  (delay_ms: int, resolver_id: int): void = "mac#bats_set_timer"
extern fun _bats_js_epoch_minutes
  (): [v:int] int v = "mac#bats_js_epoch_minutes"
extern fun _bats_epoch_millis_high
  (): [v:int] int v = "mac#bats_epoch_millis_high"
extern fun _bats_epoch_millis_low
  (): [v:int] int v = "mac#bats_epoch_millis_low"
extern fun _bats_exit
  (): void = "mac#bats_exit"
end

implement timer_set(delay_ms) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_set_timer(delay_ms, id)
in p end

implement epoch_minutes() = _bats_js_epoch_minutes()

(* The clock is read once, by the high part; JS's word is checked here *)
implement epoch_millis() = let
  val high = _bats_epoch_millis_high()
  val low = _bats_epoch_millis_low()
in
  if high < 0 then @(0, 0)
  else if low < 0 then @(0, 0)
  else if low >= 1073741824 then @(0, 0)
  else @(high, low)
end

implement exit() = _bats_exit()

implement on_timer_fire(resolver_id) =
  $P.fire(resolver_id, 0)

end (* #target wasm *)
