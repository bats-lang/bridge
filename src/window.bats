(* window -- window focus, visibility, logging for bridge *)

#include "share/atspre_staload.hats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

#pub fun focus(): void

#pub fun get_visibility(): int

#pub fun log
  {lb:agz}{n:nat}
  (level: int, msg: !$A.borrow(byte, lb, n), msg_len: int n): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

extern fun _bats_js_focus_window
  (): void = "mac#bats_js_focus_window"
extern fun _bats_js_get_visibility_state
  (): int = "mac#bats_js_get_visibility_state"
extern fun _bats_js_log
  (level: int, msg: ptr, msg_len: int): void = "mac#bats_js_log"

implement focus() = _bats_js_focus_window()

implement get_visibility() = _bats_js_get_visibility_state()

implement log{lb}{n}(level, msg, msg_len) =
  _bats_js_log(level,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(msg) end,
    msg_len)

end (* #target wasm *)
