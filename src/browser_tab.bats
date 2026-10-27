(* browser_tab -- an address opened in the system browser's tab over the
   native app

   An OAuth sign-in in a native app goes through the system browser
   (RFC 8252: an external user agent), not the app's own WebView. App
   (Capacitor): the Browser plugin opens the address in a Custom Tab
   over the app (plugins.bats, @capacitor/browser). How the reader comes
   back is app_link.bats' (the App plugin). A browser has no Browser
   plugin: there the page leaves for the address itself (nav.bats'
   navigate_away).

   There is no close (bats-lang/bridge#135): on Android a return at the
   app's own address brings its activity (singleTask) forward, which
   finishes the tab and the plugin's BrowserControllerActivity above it.
   Once that activity is destroyed, its onDestroy clears the plugin's
   instance, and Browser.close() does nothing. Between its finish and
   its onDestroy, Browser.close() would start a new
   BrowserControllerActivity, which either opens the tab again (the
   plugin's listener from open() is still set) or stays, translucent,
   over the app. So a close gives nothing on Android, and iOS is not a
   platform pwa writes. *)

#include "share/atspre_staload.hats"
staload "./nav.bats"
staload "./decompress.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* How opening a browser tab ended. JS's answer is decoded here, once: a
   code it should not send is TabNotOpened.
   Deprecated (browser_tab, bridge#240): it folds an address that is not
   https, no plugin here, an open the plugin rejected and an open that threw
   into TabNotOpened; tab_open_answer tells them apart. *)
#pub datatype tab_opened =
  | TabOpened     (* the tab is open over the app *)
  | TabNotOpened  (* not an https address, no browser, or no plugin *)

(* How opening a browser tab ended, each outcome its own. JS's answer is
   decoded here, once: the tab is open, an address that is not https
   (refused here, nothing done), no plugin here, the plugin rejected the
   open (what, as text), the open threw (what, as text: the call, or reading
   the address), and a code JS never gives. The text is none when JS could
   not write it down. Linear (the text), so the one consumer takes it apart
   with case+ ~; one no consumer takes is freed by promise's dispose. *)
#pub datavtype tab_open_answer =
  | TabOpenDone                                          (* the tab is open over the app *)
  | TabOpenNotHttps                                      (* refused here: not an https address *)
  | TabOpenNotHere                                       (* no plugin here *)
  | TabOpenRejected of $R.option([n:nat] dblob(n))       (* the plugin rejected the open: what, as text *)
  | TabOpenThrown of $R.option([n:nat] dblob(n))         (* the open threw: what, as text *)
  | TabOpenUnexpected of Int                             (* a code JS never gives *)

(* Whether the app can open an address in a browser tab: the native app
   with its Browser plugin; false in a browser *)
#pub fun browser_tab_available(): bool

(* Opens url[0, url_len) in the system browser's tab over the app;
   resolves with whether it opened. An address that is not https:// is
   refused here (nav.bats' is_https), and nothing is done.
   Deprecated (browser_tab, bridge#240): browser_tab_open_answer. *)
#pub fun browser_tab_open
  {lb:agz}{n:nat}
  (url: !$A.borrow(byte, lb, n), url_len: int n): $P.promise(tab_opened, $P.Chained)

(* browser_tab_open with every outcome its own *)
#pub fun browser_tab_open_answer
  {lb:agz}{n:nat}
  (url: !$A.borrow(byte, lb, n), url_len: int n): $P.promise(tab_open_answer, $P.Chained)

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

$UNSAFE begin
%{
extern int bats_js_browser_tab_available(void);
extern void bats_js_browser_tab_open(void*, int, int);
extern int bats_js_browser_tab_open_text(int);
%}
extern fun _bats_js_browser_tab_available
  (): int = "mac#bats_js_browser_tab_available"
extern fun _bats_js_browser_tab_open
  (url: ptr, url_len: int, resolver_id: int): void = "mac#bats_js_browser_tab_open"
extern fun _bats_js_browser_tab_open_text
  (resolver_id: int): int = "mac#bats_js_browser_tab_open_text"
end

implement browser_tab_available() = _bats_js_browser_tab_available() > 0

(* JS's code for a blob, as a handle: bridge's own atoms are the only
   ones that give one *)
fn _claimed (code: int): $R.option([n:nat] dblob(n)) =
  blob_claim($UNSAFE begin $UNSAFE.cast{blob_handle}(code) end)

(* What the plugin rejected the open with, or what threw, as text: JS kept
   it under the call's number, and none when it could not be written down *)
fn _open_text (resolver_id: int): $R.option([n:nat] dblob(n)) = let
  val handle = _bats_js_browser_tab_open_text(resolver_id)
in
  if handle <= 0 then $R.none() else _claimed(handle)
end

fn _free_text (text: $R.option([n:nat] dblob(n))): void =
  case+ text of ~$R.some(blob) => blob_free(blob) | ~$R.none() => ()

(* JS's codes: 1 the tab is open, 0 no plugin here, -2 the plugin rejected
   the open, -3 the open threw (the text of -2 and -3 kept by the call's
   number); any other is a code JS never gives *)
fn _tab_open_answer (code: Int, resolver_id: int): tab_open_answer =
  if code = 1 then TabOpenDone()
  else if code = 0 then TabOpenNotHere()
  else if code = ~2 then TabOpenRejected(_open_text(resolver_id))
  else if code = ~3 then TabOpenThrown(_open_text(resolver_id))
  else TabOpenUnexpected(code)

(* The old outcome, as it always was: opened when the plugin opened it,
   TabNotOpened for everything else (the text freed). The one change: the
   address failing to read threw out of the import before (the promise never
   settled); it is a thrown open now, so TabNotOpened *)
fn _opened (answer: tab_open_answer): tab_opened =
  case+ answer of
  | ~TabOpenDone() => TabOpened()
  | ~TabOpenNotHttps() => TabNotOpened()
  | ~TabOpenNotHere() => TabNotOpened()
  | ~TabOpenRejected(text) => let val () = _free_text(text) in TabNotOpened() end
  | ~TabOpenThrown(text) => let val () = _free_text(text) in TabNotOpened() end
  | ~TabOpenUnexpected(_) => TabNotOpened()

(* Answers nobody took. Before their first use. *)
implement $P.dispose<tab_opened>(_) = ()
implement $P.dispose<tab_open_answer>(answer) =
  case+ answer of
  | ~TabOpenDone() => ()
  | ~TabOpenNotHttps() => ()
  | ~TabOpenNotHere() => ()
  | ~TabOpenRejected(text) => _free_text(text)
  | ~TabOpenThrown(text) => _free_text(text)
  | ~TabOpenUnexpected(_) => ()

implement browser_tab_open_answer{lb}{n}(url, url_len) =
  if ~is_https(url, url_len) then $P.ret<tab_open_answer>(TabOpenNotHttps())
  else let
    val @(p, r) = $P.create<Int>()
    val id = $P.stash(r)
    val () = _bats_js_browser_tab_open(
      $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end, url_len, id)
  in $P.and_then<Int><tab_open_answer>(p, llam (code) =>
    $P.ret<tab_open_answer>(_tab_open_answer(code, id))) end

implement browser_tab_open{lb}{n}(url, url_len) =
  $P.and_then<tab_open_answer><tab_opened>(
    browser_tab_open_answer(url, url_len), llam (answer) =>
    $P.ret<tab_opened>(_opened(answer)))

end (* #target wasm *)
