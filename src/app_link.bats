(* app_link -- the native app's links out and back: an address opened in
   the system browser's tab over the app, and the addresses the app is
   opened at

   An OAuth sign-in in a native app goes through the system browser and
   comes back to the app at its own address (RFC 8252: an external user
   agent, and a private-use URI scheme for the redirect). App
   (Capacitor): the Browser plugin opens the address in a Custom Tab
   over the app (plugins.bats, @capacitor/browser), and the App plugin
   passes each address the app is opened at (its appUrlOpen, Android's
   VIEW intents, kept until a listener takes them, so one that started
   the app is passed too; @capacitor/app). The app's manifest must say
   which scheme opens it (pwa's create_android_linked). A browser has
   neither: there the page leaves for the address itself (nav.bats'
   navigate_away) and comes back to its own. *)

#include "share/atspre_staload.hats"
staload "./event.bats"
staload "./decompress.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* How opening a browser tab ended. JS's answer is decoded here, once: a
   code it should not send is TabNotOpened. *)
#pub datatype tab_opened =
  | TabOpened     (* the tab is open over the app *)
  | TabNotOpened  (* not an https address, no browser, or no plugin *)

(* Whether the app can open an address in a browser tab and be told the
   addresses it is opened at: the native app with its Browser and App
   plugins; false in a browser *)
#pub fun browser_tab_available(): bool

(* Opens url[0, url_len), an https address, in the system browser's tab
   over the app; resolves with whether it opened *)
#pub fun browser_tab_open
  {lb:agz}{n:nat}
  (url: !$A.borrow(byte, lb, n), url_len: int n): $P.promise(tab_opened, $P.Chained)

(* Closes the tab browser_tab_open opened, when it is still open: once
   the address it led to has come back to the app *)
#pub fun browser_tab_close(): void

(* A listener for the addresses the app is opened at, each passed as its
   UTF-8 bytes (an address JS cannot give, or an empty one, is not
   passed). An address that started the app is passed too, once the
   listener is set. The callback frees the blob. *)
#pub fun listen_app_link
  (listener_id: listener_id,
   callback: ([k:pos] dblob(k)) -<lincloptr1> void): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

$UNSAFE begin
%{
extern void bats_listener_set_decoded(int id, void *decoder, void *inner);
extern int bats_js_browser_tab_available(void);
extern void bats_js_browser_tab_open(void*, int, int);
extern void bats_js_browser_tab_close(void);
extern void bats_js_listen_app_link(int);
%}
extern fun _bats_js_browser_tab_available
  (): int = "mac#bats_js_browser_tab_available"
extern fun _bats_js_browser_tab_open
  (url: ptr, url_len: int, resolver_id: int): void = "mac#bats_js_browser_tab_open"
extern fun _bats_js_browser_tab_close
  (): void = "mac#bats_js_browser_tab_close"
extern fun _bats_js_listen_app_link
  (listener_id: int): void = "mac#bats_js_listen_app_link"
end

implement browser_tab_available() = _bats_js_browser_tab_available() > 0

(* An outcome nobody took: nothing to free *)
implement $P.dispose<tab_opened>(_) = ()

(* JS's codes: 1 opened, anything else not *)
fn _tab_opened (code: Int): tab_opened =
  if code = 1 then TabOpened() else TabNotOpened()

implement browser_tab_open{lb}{n}(url, url_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_browser_tab_open(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end, url_len, id)
in $P.and_then<Int><tab_opened>(p, llam (code) =>
  $P.ret<tab_opened>(_tab_opened(code))) end

implement browser_tab_close() = _bats_js_browser_tab_close()

(* The event's address: its blob, when there is one and it is not
   empty *)
fn _link (payload: event_payload): $R.option([k:pos] dblob(k)) =
  case+ event_take(payload) of
  | ~$R.some(blob) =>
    if blob_len(blob) > 0 then $R.some(blob)
    else let val () = blob_free(blob) in $R.none() end
  | ~$R.none() => $R.none()

(* The slot holds the decoder and the callback, and frees both (the
   decoder holds only the callback's pointer). *)
implement listen_app_link(listener_id, callback) = let
  val inner = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val decode = llam (payload: event_payload): int =<lincloptr1>
    case+ _link(payload) of
    | ~$R.some(blob) => let
        val call = $UNSAFE begin $UNSAFE.cast{([k:pos] dblob(k)) -<cloref1> void}(inner) end
        val () = call(blob)
      in 0 end
    | ~$R.none() => 0
  val decoder = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(decode) end
  val () = $UNSAFE begin
    $extfcall(void, "bats_listener_set_decoded", listener_id, decoder, inner) end
in _bats_js_listen_app_link(listener_id) end

end (* #target wasm *)
