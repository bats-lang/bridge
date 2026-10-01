(* app -- where the app runs, and installing it, for bridge *)

#include "share/atspre_staload.hats"
staload "./event.bats"

#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

(* Whether the page runs in the native app (Capacitor's
   isNativePlatform()), not in a browser *)
#pub fun is_native_platform(): bool

(* Whether the page is in iOS Safari's browser, not added to the Home
   Screen (navigator.standalone is false), where installing is the
   user's own Share, Add to Home Screen; false elsewhere *)
#pub fun is_ios_browser(): bool

(* Whether the browser offers to install the app now: it fired
   beforeinstallprompt, which bridge keeps from the page's start (the
   browser's own banner is held back). Browser only: an installed app,
   or the native app, has no offer. *)
#pub fun install_prompt_available(): bool

(* Shows the browser's offer to install the app; call it from a click's
   listener. The offer is used up. The promise resolves with 1 when the
   user accepted, 0 when they dismissed it, 2 when there was no offer
   (unavailable) or it failed. *)
#pub fun install_prompt(): $P.promise_pending(Int)

(* A listener for the offer's coming and going (browser only): its
   payload is one byte, 1 when there is an offer now, 0 when it was used
   or the app was installed. An offer made before the listener is set is
   not passed to it: ask install_prompt_available. *)
#pub fun listen_install_prompt
  (listener_id: listener_id,
   callback: (event_payload) -<cloref1> int): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_listener_set(int id, void *cb);
extern int bats_js_is_native_platform(void);
extern int bats_js_is_ios_browser(void);
extern int bats_js_install_prompt_available(void);
extern void bats_js_install_prompt(int);
extern void bats_js_listen_install_prompt(int);
%}
extern fun _bats_js_is_native_platform
  (): int = "mac#bats_js_is_native_platform"
extern fun _bats_js_is_ios_browser
  (): int = "mac#bats_js_is_ios_browser"
extern fun _bats_js_install_prompt_available
  (): int = "mac#bats_js_install_prompt_available"
extern fun _bats_js_install_prompt
  (resolver_id: int): void = "mac#bats_js_install_prompt"
extern fun _bats_js_listen_install_prompt
  (listener_id: int): void = "mac#bats_js_listen_install_prompt"
end

implement is_native_platform() = _bats_js_is_native_platform() > 0

implement is_ios_browser() = _bats_js_is_ios_browser() > 0

implement install_prompt_available() = _bats_js_install_prompt_available() > 0

implement install_prompt() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_install_prompt(id)
in p end

implement listen_install_prompt(listener_id, callback) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val () = $UNSAFE begin $extfcall(void, "bats_listener_set", listener_id, cbp) end
in _bats_js_listen_install_prompt(listener_id) end

end (* #target wasm *)
