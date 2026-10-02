(* window -- window focus, visibility, logging for bridge *)

#include "share/atspre_staload.hats"

#use array as A
#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

#pub fun focus(): void

(* Whether the page is shown. JS's answer is decoded here, once:
   anything but its hidden is Visible. *)
#pub datatype visibility =
  | Visible
  | Hidden

(* A log line's level *)
#pub datatype log_level =
  | Debug
  | Info
  | Warn
  | Error

#pub fun get_visibility(): visibility

(* Keeps the screen from sleeping while on is true (a Screen Wake Lock,
   taken again whenever the page is shown); false lets it sleep again *)
#pub fun keep_awake(on: bool): void

(* How a wake lock request ended. JS's answer is decoded here, once:
   anything but its 1 is WakeLockRefused. *)
#pub datatype wake_lock =
  | WakeLockHeld     (* the screen is kept awake until it is lost *)
  | WakeLockRefused  (* refused, or there are no wake locks here *)

(* Asks for a Screen Wake Lock: one atom, with no policy (keep_awake
   decides when). The one held is the one wake_lock_release lets go *)
#pub fun wake_lock_request(): $P.promise(wake_lock, $P.Chained)

(* Releases the wake lock held, if any *)
#pub fun wake_lock_release(): void

(* Resolves once the wake lock held is lost (released, or dropped by the
   browser, as it is when the page is hidden); at once when none is
   held. JS's answer carries nothing, so it is a bool, always true *)
#pub fun wake_lock_lost(): $P.promise(bool, $P.Chained)

(* Resolves at the page's next visibility change, with its visibility
   then *)
#pub fun visibility_next(): $P.promise(visibility, $P.Chained)

#pub fun log
  {lb:agz}{n:nat}
  (level: log_level, msg: !$A.borrow(byte, lb, n), msg_len: int n): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_js_focus_window(void);
extern int bats_js_get_visibility_state(void);
extern void bats_js_wake_lock_request(int);
extern void bats_js_wake_lock_release(void);
extern void bats_js_wake_lock_lost(int);
extern void bats_js_visibility_next(int);
extern void bats_js_log(int, void*, int);
%}
extern fun _bats_js_focus_window
  (): void = "mac#bats_js_focus_window"
extern fun _bats_js_get_visibility_state
  (): int = "mac#bats_js_get_visibility_state"
extern fun _bats_js_wake_lock_request
  (resolver_id: int): void = "mac#bats_js_wake_lock_request"
extern fun _bats_js_wake_lock_release
  (): void = "mac#bats_js_wake_lock_release"
extern fun _bats_js_wake_lock_lost
  (resolver_id: int): void = "mac#bats_js_wake_lock_lost"
extern fun _bats_js_visibility_next
  (resolver_id: int): void = "mac#bats_js_visibility_next"
extern fun _bats_js_log
  (level: int, msg: ptr, msg_len: int): void = "mac#bats_js_log"

end (* $UNSAFE *)

implement focus() = _bats_js_focus_window()

(* JS's codes: 1 hidden, 0 visible *)
implement get_visibility() =
  if _bats_js_get_visibility_state() = 1 then Hidden() else Visible()

(* JS's codes: 1 held, anything else refused *)
fn _wake_lock (code: Int): wake_lock =
  if code = 1 then WakeLockHeld() else WakeLockRefused()

(* An answer nobody took: nothing to free. Before wake_lock_request, its
   first use. *)
implement $P.dispose<wake_lock>(_) = ()

implement wake_lock_request() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_wake_lock_request(id)
in $P.and_then<Int><wake_lock>(p, llam (code) => $P.ret<wake_lock>(_wake_lock(code))) end

implement wake_lock_release() = _bats_js_wake_lock_release()

implement wake_lock_lost() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_wake_lock_lost(id)
in $P.and_then<Int><bool>(p, llam (_) => $P.ret<bool>(true)) end

(* A visibility nobody took: nothing to free. Before visibility_next,
   its first use. *)
implement $P.dispose<visibility>(_) = ()

(* JS's codes: 1 hidden, anything else visible *)
implement visibility_next() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_visibility_next(id)
in $P.and_then<Int><visibility>(p, llam (code) =>
  $P.ret<visibility>(if code = 1 then Hidden() else Visible())) end

(* keep_awake's state: whether the app wants the screen awake, and
   whether a round of taking a lock (below) is under way *)
val _wake_wanted = ref<bool>(false)
val _wake_running = ref<bool>(false)

(* How many rounds keep_awake(true) runs at most: each is a lock lost
   (the page hidden and shown again) or refused. A metric needs a bound;
   this one is far past a session's. After it, the screen may sleep
   until keep_awake(true) is called again *)
#define WAKE_ROUNDS 100000

(* One round: while a lock is wanted, wait for the page to be shown,
   take a lock, and hold it until it is lost (the browser drops it when
   the page is hidden) or refused, then start the next. It stops once
   the lock is no longer wanted; keep_awake(false) releases the one
   held, which ends the wait for its loss *)
fun _wake_round {rounds:nat} .<rounds>. (rounds: int rounds): void =
  if not(!_wake_wanted) then !_wake_running := false
  else if rounds <= 0 then !_wake_running := false
  else (case+ get_visibility() of
    | Hidden() => $P.finish<visibility>(visibility_next(), llam (_) => _wake_round(rounds - 1))
    | Visible() => $P.finish<wake_lock>(wake_lock_request(), llam (answer) =>
        case+ answer of
        (* refused (a browser may refuse one now and grant it later):
           asked for again once the page is shown again *)
        | WakeLockRefused() => $P.finish<visibility>(visibility_next(), llam (_) => _wake_round(rounds - 1))
        | WakeLockHeld() =>
          if not(!_wake_wanted) then let
            (* no longer wanted by the time it came: let it go *)
            val () = wake_lock_release()
          in !_wake_running := false end
          else $P.finish<bool>(wake_lock_lost(), llam (_) => _wake_round(rounds - 1))))

implement keep_awake(on) = let
  val () = !_wake_wanted := on
in
  if on then
    (if !_wake_running then ()
     else let val () = !_wake_running := true in _wake_round(WAKE_ROUNDS) end)
  else wake_lock_release()
end

(* JS's codes: 0 debug, 1 info, 2 warn, 3 error *)
fn _log_level_code (level: log_level): int =
  case+ level of
  | Debug() => 0
  | Info() => 1
  | Warn() => 2
  | Error() => 3

implement log{lb}{n}(level, msg, msg_len) =
  _bats_js_log(_log_level_code(level),
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(msg) end,
    msg_len)

end (* #target wasm *)
