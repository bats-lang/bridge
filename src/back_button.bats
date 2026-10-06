(* back_button -- Android's Back, in the native app

   Android's system Back (the button, or the gesture from either edge)
   goes to the app: App (Capacitor): the App plugin's backButton event
   (@capacitor/app). Once a listener is set the App plugin no longer
   goes back in the WebView's history itself, so the app decides what
   Back does: close what is open, go back a screen, or, where there is
   nothing to go back to, leave as Android does at an app's root (since
   Android 12 the system moves a root activity's task to the background
   rather than finishing it: App's minimizeApp, moveTaskToBack). A
   browser has no App plugin: there Back is the history's (nav.bats). *)

#include "share/atspre_staload.hats"
staload "./event.bats"

(* ============================================================
   Public API
   ============================================================ *)

(* Whether the app hears Android's Back: the native app with its App
   plugin; false in a browser *)
#pub fun back_button_available(): bool

(* A listener for Android's Back, called once for each press. The
   event's one field (canGoBack, the WebView's own history) is not
   passed: an app that hears Back keeps its own *)
#pub fun listen_back_button
  (listener_id: listener_id,
   callback: () -<lincloptr1> void): void

(* The app moved to the background, as Android does at an app's root
   (App's minimizeApp); nothing in a browser *)
#pub fun app_minimize(): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

$UNSAFE begin
%{
extern void bats_listener_set_decoded(int id, void *decoder, void *inner);
extern int bats_js_back_button_available(void);
extern void bats_js_listen_back_button(int);
extern void bats_js_app_minimize(void);
%}
extern fun _bats_js_back_button_available
  (): int = "mac#bats_js_back_button_available"
extern fun _bats_js_listen_back_button
  (listener_id: int): void = "mac#bats_js_listen_back_button"
extern fun _bats_js_app_minimize
  (): void = "mac#bats_js_app_minimize"
end

implement back_button_available() = _bats_js_back_button_available() > 0

implement app_minimize() = _bats_js_app_minimize()

(* The event carries no payload. The slot holds the decoder and the
   callback, and frees both (the decoder holds only the callback's
   pointer). *)
implement listen_back_button(listener_id, callback) = let
  val inner = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val decode = llam (_: event_payload): int =<lincloptr1> let
    val call = $UNSAFE begin $UNSAFE.cast{() -<cloref1> void}(inner) end
    val () = call()
  in 0 end
  val decoder = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(decode) end
  val () = $UNSAFE begin
    $extfcall(void, "bats_listener_set_decoded", listener_id, decoder, inner) end
in _bats_js_listen_back_button(listener_id) end

end (* #target wasm *)
