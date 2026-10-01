(* app -- where the app runs, and installing it, for bridge *)

#include "share/atspre_staload.hats"
staload "./event.bats"

#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

(* How the offer to install ended. JS's answer is decoded here, once: a
   code it should not send is InstallUnavailable. *)
#pub datatype install_outcome =
  | InstallAccepted     (* the user installed the app *)
  | InstallDismissed    (* the user said no *)
  | InstallUnavailable  (* there was no offer, or showing it failed *)

(* The offer's coming and going, as listen_install_prompt passes it *)
#pub datatype install_offer =
  | InstallOffered    (* there is an offer now *)
  | InstallWithdrawn  (* it was used, or the app was installed *)

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
   listener. The offer is used up. The promise resolves with how it
   ended. *)
#pub fun install_prompt(): $P.promise(install_outcome, $P.Chained)

(* A listener for the offer's coming and going (browser only), passed
   whether there is an offer now (install_prompt_available, read as the
   event comes). An offer made before the listener is set is not passed
   to it: ask install_prompt_available. *)
#pub fun listen_install_prompt
  (listener_id: listener_id,
   callback: (install_offer) -<cloref1> void): void

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

(* JS's codes: 1 accepted, 0 dismissed, 2 no offer or failed *)
fn _install_outcome (code: Int): install_outcome =
  if code = 1 then InstallAccepted()
  else if code = 0 then InstallDismissed()
  else InstallUnavailable()

implement install_prompt() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_install_prompt(id)
in $P.and_then<Int><install_outcome>(p, lam (code) =>
  $P.ret<install_outcome>(_install_outcome(code))) end

(* The event carries no payload: whether there is an offer is read as it
   comes, so there is nothing to decode that could be wrong *)
implement listen_install_prompt(listener_id, callback) = let
  val decode = lam (_: event_payload): int =<cloref1> let
    val () = callback(if install_prompt_available()
      then InstallOffered() else InstallWithdrawn())
  in 0 end
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(decode) end
  val () = $UNSAFE begin $extfcall(void, "bats_listener_set", listener_id, cbp) end
in _bats_js_listen_install_prompt(listener_id) end

end (* #target wasm *)
