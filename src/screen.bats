(* screen -- full screen, the rotation lock and the brightness for bridge *)

#include "share/atspre_staload.hats"
staload "./event.bats"

#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

(* Full screen's change, as listen_fullscreen passes it *)
#pub datatype fullscreen_change =
  | FullscreenEntered
  | FullscreenLeft

(* How a rotation lock ended. JS's answer is decoded here, once:
   anything but its yes is LockRefused. *)
#pub datatype lock_outcome =
  | Locked       (* the rotation is locked to the one the screen has *)
  | LockRefused  (* refused, or it cannot be locked here *)

(* The screen's brightness, as brightness_get reads it. JS's answer is
   decoded here, once: anything outside 0 to 100 that is not the
   system's own is BrightnessUnreadable. Linear: Brightness is boxed and
   there is no garbage collector, so the one consumer takes it apart
   with case+ ~, which frees it; a reading no consumer takes is freed by
   promise's dispose. *)
#pub datavtype brightness_reading =
  | Brightness of [n:nat | n <= 100] int n  (* percent *)
  | SystemBrightness      (* the app leaves it to the system *)
  | BrightnessUnreadable  (* it cannot be read here (not the app) *)

(* A brightness to set: a level in percent, or the system's own. Linear,
   so the one brightness_set takes is freed there (there is no garbage
   collector). *)
#pub datavtype brightness_setting =
  | Level of [n:nat | n <= 100] int n
  | FollowSystem

(* Whether full screen can be had here. Browser: the Fullscreen API
   (document.fullscreenEnabled). App (Capacitor): Capacitor's SystemBars,
   which hides the system bars. *)
#pub fun fullscreen_available(): bool

(* Goes into full screen. Browser: the document element's
   requestFullscreen, which needs the user's activation (call it from a
   click's listener). App: the system bars, the status bar and the
   navigation bar, hidden (SystemBars.hide with no bar named: Android's
   WindowInsetsCompat.Type.systemBars()). Nothing when it is not
   available. *)
#pub fun fullscreen_enter(): void

(* Leaves full screen (the system bars shown again in the app,
   SystemBars.show with no bar named) *)
#pub fun fullscreen_exit(): void

(* Whether the page is in full screen now (browser: document's
   fullscreenElement; app: the bars hidden by fullscreen_enter) *)
#pub fun fullscreen_active(): bool

(* A listener for full screen's changes, browser and app, passed whether
   the page went into full screen or left it (fullscreen_active, read
   as the event comes). Browser: each fullscreenchange (Escape leaves
   full screen too). App: once fullscreen_enter or fullscreen_exit has
   hidden or shown the bars. *)
#pub fun listen_fullscreen
  (listener_id: listener_id,
   callback: (fullscreen_change) -<lincloptr1> void): void

(* The app's system bars, as its native side reports them: which of the
   status bar and the navigation bar are shown (Android's
   WindowInsets.isVisible(statusBars()), isVisible(navigationBars())) *)
#pub datatype system_bars =
  | BarsShown           (* both *)
  | StatusBarShown      (* the status bar alone *)
  | NavigationBarShown  (* the navigation bar alone *)
  | BarsHidden          (* neither *)

(* Whether the system bars are reported here: once the app's native side
   has reported them (batsNative.systemBars); never in a browser *)
#pub fun system_bars_available(): bool

(* A listener for the system bars, passed each report of them by the
   app's native side (batsNative.systemBars, at each of Android's window
   insets dispatches, read as the event comes): whatever changed them,
   fullscreen_enter and fullscreen_exit, or the system (a swipe from the
   screen's edge brings hidden bars back). The latest report made before
   the listener is passed to it as it is set. None in a browser. *)
#pub fun listen_system_bars
  (listener_id: listener_id,
   callback: (system_bars) -<lincloptr1> void): void

(* Whether the rotation can be locked here and now. Browser:
   screen.orientation.lock, where a browser allows it (the app installed,
   or in full screen). App: the ScreenOrientation plugin. *)
#pub fun orientation_available(): bool

(* Locks the rotation to the one the screen has now (browser, where it is
   allowed; else the app's plugin); the promise resolves once it is
   locked, or was refused *)
#pub fun orientation_lock_current(): $P.promise(lock_outcome, $P.Chained)

(* Lets the screen rotate again (browser and app) *)
#pub fun orientation_unlock(): void

(* Whether the screen's brightness can be set: the app only (the
   ScreenBrightness plugin); a web page cannot set it *)
#pub fun brightness_available(): bool

(* The screen's brightness (app only; BrightnessUnreadable elsewhere) *)
#pub fun brightness_get(): $P.promise(brightness_reading, $P.Chained)

(* Sets the screen's brightness while the app is shown: a level in
   percent, or FollowSystem to leave it to the system again (app only;
   nothing elsewhere) *)
#pub fun brightness_set (setting: brightness_setting): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_listener_set_decoded(int id, void *decoder, void *inner);
extern int bats_js_fullscreen_available(void);
extern int bats_js_fullscreen_active(void);
extern void bats_js_fullscreen_set(int);
extern void bats_js_listen_fullscreen(int);
extern int bats_js_system_bars(void);
extern void bats_js_listen_system_bars(int);
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
extern fun _bats_js_system_bars
  (): int = "mac#bats_js_system_bars"
extern fun _bats_js_listen_system_bars
  (listener_id: int): void = "mac#bats_js_listen_system_bars"
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

(* The event carries no payload: full screen's state is read as it
   comes, so there is nothing to decode that could be wrong. The slot
   holds the decoder and the callback, and frees both (the decoder
   holds only the callback's pointer). *)
implement listen_fullscreen(listener_id, callback) = let
  val inner = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val decode = llam (payload: event_payload): int =<lincloptr1> let
    val call = $UNSAFE begin $UNSAFE.cast{(fullscreen_change) -<cloref1> void}(inner) end
    val () = call(if fullscreen_active()
      then FullscreenEntered() else FullscreenLeft())
  in 0 end
  val decoder = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(decode) end
  val () = $UNSAFE begin
    $extfcall(void, "bats_listener_set_decoded", listener_id, decoder, inner) end
in _bats_js_listen_fullscreen(listener_id) end

implement system_bars_available() = _bats_js_system_bars() >= 0

(* JS's report, decoded here, once: bit 1 the status bar shown, bit 2
   the navigation bar *)
fn _system_bars (code: int): system_bars =
  if code = 3 then BarsShown()
  else if code = 1 then StatusBarShown()
  else if code = 2 then NavigationBarShown()
  else BarsHidden()

(* As listen_fullscreen: no payload, the report read as the event comes
   (JS fires only once there is one) *)
implement listen_system_bars(listener_id, callback) = let
  val inner = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val decode = llam (payload: event_payload): int =<lincloptr1> let
    val code = _bats_js_system_bars()
  in
    if code < 0 then 0
    else let
      val call = $UNSAFE begin $UNSAFE.cast{(system_bars) -<cloref1> void}(inner) end
      val () = call(_system_bars(code))
    in 0 end
  end
  val decoder = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(decode) end
  val () = $UNSAFE begin
    $extfcall(void, "bats_listener_set_decoded", listener_id, decoder, inner) end
in _bats_js_listen_system_bars(listener_id) end

implement orientation_available() = _bats_js_orientation_available() > 0

(* JS's codes: 1 locked, 0 refused *)
fn _lock_outcome (code: Int): lock_outcome =
  if code = 1 then Locked() else LockRefused()

(* An outcome nobody took: nothing to free *)
implement $P.dispose<lock_outcome>(_) = ()

implement orientation_lock_current() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_orientation_lock(id)
in $P.and_then<Int><lock_outcome>(p, llam (code) =>
  $P.ret<lock_outcome>(_lock_outcome(code))) end

implement orientation_unlock() = _bats_js_orientation_unlock()

implement brightness_available() = _bats_js_brightness_available() > 0

(* JS's codes: 0 to 100 percent, -1 the system's own, -2 unreadable *)
fn _brightness_reading (code: Int): brightness_reading =
  if code = ~1 then SystemBrightness()
  else if code < 0 then BrightnessUnreadable()
  else if code > 100 then BrightnessUnreadable()
  else Brightness(code)

(* A reading nobody took: freed. ATS2 resolves a template's instances
   in file order, so this comes before brightness_get, its first use. *)
implement $P.dispose<brightness_reading>(reading) =
  case+ reading of
  | ~Brightness(_) => ()
  | ~SystemBrightness() => ()
  | ~BrightnessUnreadable() => ()

implement brightness_get() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_brightness_get(id)
in $P.and_then<Int><brightness_reading>(p, llam (code) =>
  $P.ret<brightness_reading>(_brightness_reading(code))) end

(* JS's codes: 0 to 100 percent, -1 the system's own *)
implement brightness_set(setting) =
  case+ setting of
  | ~Level(level) => _bats_js_brightness_set(level)
  | ~FollowSystem() => _bats_js_brightness_set(~1)

end (* #target wasm *)
