(* browser_tab -- an address opened in the system browser's tab over the
   native app

   An OAuth sign-in in a native app goes through the system browser
   (RFC 8252: an external user agent), not the app's own WebView. App
   (Capacitor): the Browser plugin opens the address in a Custom Tab
   over the app (plugins.bats, @capacitor/browser). How the reader comes
   back is app_link.bats' (the App plugin). A browser has no Browser
   plugin: there the page leaves for the address itself (nav.bats'
   navigate_away).

   There is no close: on Android a return at the app's own address
   brings its activity (singleTask) forward, which finishes the tab and
   the plugin's BrowserControllerActivity above it; Browser.close() after
   that starts a new BrowserControllerActivity, which nothing finishes
   (bats-lang/bridge#130). *)

#include "share/atspre_staload.hats"
staload "./nav.bats"

#use array as A
#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

(* How opening a browser tab ended. JS's answer is decoded here, once: a
   code it should not send is TabNotOpened. *)
#pub datatype tab_opened =
  | TabOpened     (* the tab is open over the app *)
  | TabNotOpened  (* not an https address, no browser, or no plugin *)

(* Whether the app can open an address in a browser tab: the native app
   with its Browser plugin; false in a browser *)
#pub fun browser_tab_available(): bool

(* Opens url[0, url_len) in the system browser's tab over the app;
   resolves with whether it opened. An address that is not https:// is
   refused here (nav.bats' is_https), and nothing is done *)
#pub fun browser_tab_open
  {lb:agz}{n:nat}
  (url: !$A.borrow(byte, lb, n), url_len: int n): $P.promise(tab_opened, $P.Chained)

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

$UNSAFE begin
%{
extern int bats_js_browser_tab_available(void);
extern void bats_js_browser_tab_open(void*, int, int);
%}
extern fun _bats_js_browser_tab_available
  (): int = "mac#bats_js_browser_tab_available"
extern fun _bats_js_browser_tab_open
  (url: ptr, url_len: int, resolver_id: int): void = "mac#bats_js_browser_tab_open"
end

implement browser_tab_available() = _bats_js_browser_tab_available() > 0

(* An outcome nobody took: nothing to free *)
implement $P.dispose<tab_opened>(_) = ()

(* JS's codes: 1 opened, anything else not *)
fn _tab_opened (code: Int): tab_opened =
  if code = 1 then TabOpened() else TabNotOpened()

implement browser_tab_open{lb}{n}(url, url_len) =
  if ~is_https(url, url_len) then $P.ret<tab_opened>(TabNotOpened())
  else let
    val @(p, r) = $P.create<Int>()
    val id = $P.stash(r)
    val () = _bats_js_browser_tab_open(
      $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end, url_len, id)
  in $P.and_then<Int><tab_opened>(p, llam (code) =>
    $P.ret<tab_opened>(_tab_opened(code))) end

end (* #target wasm *)
