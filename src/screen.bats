(* screen -- full screen, the rotation lock and the brightness for bridge *)

#include "share/atspre_staload.hats"
staload "./event.bats"

#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

(* Whether full screen can be had here. Browser: the Fullscreen API
   (document.fullscreenEnabled). App (Capacitor): the StatusBar plugin,
   which hides the status bar (and the NavigationBar plugin, when the app
   has it, the navigation bar). *)
#pub fun fullscreen_available(): bool

(* Goes into full screen. Browser: the document element's
   requestFullscreen, which needs the user's activation (call it from a
   click's listener). App: the bars hidden. Nothing when it is not
   available. *)
#pub fun fullscreen_enter(): void

(* Leaves full screen (the bars shown again in the app) *)
#pub fun fullscreen_exit(): void

(* Whether the page is in full screen now (browser: document's
   fullscreenElement; app: the bars hidden by fullscreen_enter) *)
#pub fun fullscreen_active(): bool

(* A listener for full screen's changes, browser and app: its payload is
   one byte, 1 in full screen and 0 out of it. Browser: each
   fullscreenchange (Escape leaves full screen too). App: once
   fullscreen_enter or fullscreen_exit has hidden or shown the bars. *)
#pub fun listen_fullscreen
  (listener_id: listener_id,
   callback: (event_payload) -<cloref1> int): void

(* Whether the rotation can be locked here and now. Browser:
   screen.orientation.lock, where a browser allows it (the app installed,
   or in full screen). App: the ScreenOrientation plugin. *)
#pub fun orientation_available(): bool

(* Locks the rotation to the one the screen has now (browser, where it is
   allowed; else the app's plugin); the promise resolves with 1 once it
   is locked, 0 when it was refused or cannot be locked here *)
#pub fun orientation_lock_current(): $P.promise_pending(Int)

(* Lets the screen rotate again (browser and app) *)
#pub fun orientation_unlock(): void

(* Whether the screen's brightness can be set: the app only (the
   ScreenBrightness plugin); a web page cannot set it *)
#pub fun brightness_available(): bool

(* The screen's brightness (app only): the promise resolves with 0 to
   100, -1 when the app leaves it to the system, -2 when it cannot be
   read (not available) *)
#pub fun brightness_get(): $P.promise_pending(Int)

(* Sets the screen's brightness to level percent while the app is shown
   (app only; nothing elsewhere) *)
#pub fun brightness_set {level:nat | level <= 100} (level: int level): void

(* Leaves the brightness to the system again (app only) *)
#pub fun brightness_system(): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_listener_set(int id, void *cb);
extern int bats_js_fullscreen_available(void);
extern int bats_js_fullscreen_active(void);
extern void bats_js_fullscreen_set(int);
extern void bats_js_listen_fullscreen(int);
extern int bats_js_orientation_available(void);
extern void bats_js_orientation_lock(int);
extern void bats_js_orientation_unlock(void);
extern int bats_js_brightness_available(void);
extern void bats_js_brightness_get(int);
extern void bats_js_brightness_set(int);
%}
extern fun _bats_js_fullscreen_available
  (): int = "mac#bats_js_fullscreen_available"
extern fun _bats_js_fullscreen_active
  (): int = "mac#bats_js_fullscreen_active"
extern fun _bats_js_fullscreen_set
  (on: int): void = "mac#bats_js_fullscreen_set"
extern fun _bats_js_listen_fullscreen
  (listener_id: int): void = "mac#bats_js_listen_fullscreen"
extern fun _bats_js_orientation_available
  (): int = "mac#bats_js_orientation_available"
extern fun _bats_js_orientation_lock
  (resolver_id: int): void = "mac#bats_js_orientation_lock"
extern fun _bats_js_orientation_unlock
  (): void = "mac#bats_js_orientation_unlock"
extern fun _bats_js_brightness_available
  (): int = "mac#bats_js_brightness_available"
extern fun _bats_js_brightness_get
  (resolver_id: int): void = "mac#bats_js_brightness_get"
extern fun _bats_js_brightness_set
  (level: int): void = "mac#bats_js_brightness_set"
end

implement fullscreen_available() = _bats_js_fullscreen_available() > 0

implement fullscreen_enter() = _bats_js_fullscreen_set(1)

implement fullscreen_exit() = _bats_js_fullscreen_set(0)

implement fullscreen_active() = _bats_js_fullscreen_active() > 0

implement listen_fullscreen(listener_id, callback) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val () = $UNSAFE begin $extfcall(void, "bats_listener_set", listener_id, cbp) end
in _bats_js_listen_fullscreen(listener_id) end

implement orientation_available() = _bats_js_orientation_available() > 0

implement orientation_lock_current() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_orientation_lock(id)
in p end

implement orientation_unlock() = _bats_js_orientation_unlock()

implement brightness_available() = _bats_js_brightness_available() > 0

implement brightness_get() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_brightness_get(id)
in p end

implement brightness_set{level}(level) = _bats_js_brightness_set(level)

implement brightness_system() = _bats_js_brightness_set(~1)

end (* #target wasm *)
