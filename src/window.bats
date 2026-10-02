(* window -- window focus, visibility, logging for bridge *)

#include "share/atspre_staload.hats"

#use array as A

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
extern void bats_js_keep_awake(int);
extern void bats_js_log(int, void*, int);
%}
extern fun _bats_js_focus_window
  (): void = "mac#bats_js_focus_window"
extern fun _bats_js_get_visibility_state
  (): int = "mac#bats_js_get_visibility_state"
extern fun _bats_js_keep_awake
  (on: int): void = "mac#bats_js_keep_awake"
extern fun _bats_js_log
  (level: int, msg: ptr, msg_len: int): void = "mac#bats_js_log"

implement focus() = _bats_js_focus_window()

(* JS's codes: 1 hidden, 0 visible *)
implement get_visibility() =
  if _bats_js_get_visibility_state() = 1 then Hidden() else Visible()

implement keep_awake(on) = _bats_js_keep_awake(if on then 1 else 0)

(* JS's codes: 0 debug, 1 info, 2 warn, 3 error *)
fn _log_level_code (level: log_level): int =
  case+ level of
  | Debug() => 0
  | Info() => 1
  | Warn() => 2
  | Error() => 3

implement log{lb}{n}(level, msg, msg_len) =
  _bats_js_log(_log_level_code(level),
    $UNSAFE.castvwtp1{ptr}(msg),
    msg_len)

end (* $UNSAFE *)
end (* #target wasm *)
