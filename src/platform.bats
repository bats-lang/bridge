(* platform -- the browser engine, the operating system and the app shell the page runs in, for bridge

   Primitives only (bridge#191, quire#688): bridge reports what the platform
   says and the app decides what to do with it. JS writes down five facts as
   they are (navigator.userAgent, navigator.userAgentData.platform,
   navigator.platform, navigator.maxTouchPoints, Capacitor's getPlatform());
   Bats decodes them here, once, with case+. Every outcome is a constructor
   of its own, and what no rule recognises is an explicit ...Unexpected that
   keeps the fact it could not read. The desktop environment (GNOME, KDE) is
   not readable from a page: no browser API reports it, so there is no field
   for it. Why each fact, and how reliable it is: bridge's CLAUDE.md,
   "Platform". *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* Which of the facts a reading rests on *)
#pub datatype platform_source =
  | SourceUserAgent            (* navigator.userAgent *)
  | SourceUserAgentPlatform    (* navigator.userAgentData.platform *)
  | SourceNavigatorPlatform    (* navigator.platform *)
  | SourceTouchPoints          (* navigator.maxTouchPoints, written as its decimal digits *)
  | SourceCapacitor            (* Capacitor.getPlatform() *)

(* One fact, as JS wrote it down. Each form is its own: the text of a string
   (UTF-8, as TextEncoder writes it: a lone surrogate becomes U+FFFD), a
   property the platform does not have (undefined), a read that threw (what,
   as text; none when JS could not write it down), a value that is not a
   string (a number, for maxTouchPoints; what, as text), and a code JS never
   gives. Linear (the text), so the one consumer takes it apart with case+ ~
   or frees it with platform_fact_free. *)
#pub datavtype platform_fact =
  | PlatformFactText of ([n:nat] dblob(n))
  | PlatformFactAbsent
  | PlatformFactThrew of $R.option([n:nat] dblob(n))
  | PlatformFactNotText of $R.option([n:nat] dblob(n))
  | PlatformFactCode of Int

(* The engine the page is drawn by, from the user agent's tokens: Firefox/ is
   Gecko, Chrome/ is Blink (Edge, Opera, Samsung Internet and Android WebView
   carry it too), AppleWebKit/ without Chrome/ is WebKit, and CriOS/, FxiOS/
   and EdgiOS/ are WebKit (every iOS browser draws with WebKit). Only the
   first 2048 bytes of the text are read. *)
#pub datavtype engine_reading =
  | EngineBlink
  | EngineWebKit
  | EngineGecko
  | EngineUnexpected of (platform_source, platform_fact)  (* no token above: the user agent as JS wrote it *)

(* The operating system, from the user agent's tokens, else
   userAgentData.platform, else navigator.platform (the first of them that
   names one). A Macintosh that reports more than one touch point is an iPad
   in its desktop mode (IpadOs); one that reports one or none, or no
   maxTouchPoints, is a Mac. ChromeOs is its own (it says Linux too). *)
#pub datavtype os_reading =
  | OsAndroid
  | OsIos
  | OsIpadOs
  | OsMacOs
  | OsWindows
  | OsLinux
  | OsChromeOs
  | OsUnexpected of (platform_source, platform_fact)  (* no source names one, or maxTouchPoints is no count: that fact *)

(* The system an app shell runs on *)
#pub datatype app_system =
  | AppIos
  | AppAndroid

(* Whether the page is in a browser or in an app's WebView. Capacitor's
   getPlatform() says ios or android in its native app (ShellApp); with none
   (or web) the user agent decides: an Android WebView has "; wv)", and a
   WKWebView has AppleWebKit/ but not Safari/ (ShellWebView; an app can set
   its user agent, then the page looks like a browser). *)
#pub datavtype shell_reading =
  | ShellBrowser
  | ShellApp of app_system
  | ShellWebView
  | ShellUnexpected of (platform_source, platform_fact)  (* Capacitor says something else: that fact *)

(* Everything platform_read reads, each part its own *)
#pub datavtype platform_reading =
  | PlatformIs of (engine_reading, os_reading, shell_reading)

(* Whether the page can read the platform's words: there is a navigator *)
#pub fun platform_available(): bool

(* Reads and decodes the platform's words. Linear: the one consumer takes it
   apart with case+ ~, or frees it with platform_free. *)
#pub fun platform_read(): platform_reading

#pub fun platform_fact_free(fact: platform_fact): void

#pub fun platform_free(reading: platform_reading): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

$UNSAFE begin
%{
extern int bats_js_platform_available(void);
extern int bats_js_platform_fact(int);
extern int bats_js_platform_odd(int);
%}
extern fun _bats_js_platform_available
  (): int = "mac#bats_js_platform_available"
extern fun _bats_js_platform_fact
  (kind: int): [v:int] int v = "mac#bats_js_platform_fact"
extern fun _bats_js_platform_odd
  (kind: int): [v:int] int v = "mac#bats_js_platform_odd"
end

implement platform_available() = _bats_js_platform_available() > 0

(* JS's code for a blob, as a handle: bridge's own atoms are the only ones
   that give one *)
fn _claimed (code: int): $R.option([n:nat] dblob(n)) =
  blob_claim($UNSAFE begin $UNSAFE.cast{blob_handle}(code) end)

fn _free_text (text: $R.option([n:nat] dblob(n))): void =
  case+ text of ~$R.some(blob) => blob_free(blob) | ~$R.none() => ()

(* The text of a value that threw or was no string, kept by JS under the
   fact's number; none when it could not be written down *)
fn _odd_text (kind: int): $R.option([n:nat] dblob(n)) = let
  val handle = _bats_js_platform_odd(kind)
in
  if handle <= 0 then $R.none() else _claimed(handle)
end

(* JS's codes: a blob's handle (positive) is the text, 0 the property is not
   there, -1 reading it threw, -2 it is not a string (the text of -1 and -2
   kept by the fact's number); any other is a code JS never gives *)
fn _fact (kind: int): platform_fact = let
  val code = _bats_js_platform_fact(kind)
in
  if code > 0 then
    (case+ _claimed(code) of
     | ~$R.some(blob) => PlatformFactText(blob)
     | ~$R.none() => PlatformFactCode(code))
  else if code = 0 then PlatformFactAbsent()
  else if code = ~1 then PlatformFactThrew(_odd_text(kind))
  else if code = ~2 then PlatformFactNotText(_odd_text(kind))
  else PlatformFactCode(code)
end

implement platform_fact_free(fact) =
  case+ fact of
  | ~PlatformFactText(blob) => blob_free(blob)
  | ~PlatformFactAbsent() => ()
  | ~PlatformFactThrew(text) => _free_text(text)
  | ~PlatformFactNotText(text) => _free_text(text)
  | ~PlatformFactCode(_) => ()

(* The facts' numbers in JS *)
fn _user_agent (): platform_fact = _fact(0)
fn _user_agent_platform (): platform_fact = _fact(1)
fn _navigator_platform (): platform_fact = _fact(2)
fn _capacitor (): platform_fact = _fact(3)
fn _touch_points (): platform_fact = _fact(4)

(* ---- the first 2048 bytes of a text, to look for tokens in ---- *)

datavtype head =
  | {l:agz}{n:nat | n <= 2048} Head of ($A.arr(byte, l, 2048), int n)
  | NoHead

fn _head_blob {n:nat} (blob: !dblob(n)): head = let
  val n = blob_len(blob)
  val bytes = $A.alloc<byte>(2048)
in
  if n <= 2048 then let
    val () = blob_read(blob, 0, bytes, n)
  in Head(bytes, n) end
  else let
    val () = blob_read(blob, 0, bytes, 2048)
  in Head(bytes, 2048) end
end

fn _head_of (fact: !platform_fact): head =
  case+ fact of
  | @PlatformFactText(blob) => let
      val head = _head_blob(blob)
      prval () = fold@(fact)
    in head end
  | PlatformFactAbsent() => NoHead()
  | @PlatformFactThrew(_) => let prval () = fold@(fact) in NoHead() end
  | @PlatformFactNotText(_) => let prval () = fold@(fact) in NoHead() end
  | @PlatformFactCode(_) => let prval () = fold@(fact) in NoHead() end

fn _head_free (head: head): void =
  case+ head of
  | ~Head(bytes, _) => $A.free<byte>(bytes)
  | ~NoHead() => ()

fun _starts {l:agz}{size:nat}{length:nat | length <= size}{n:nat}{at:nat}{j:nat | j <= n} .<n - j>.
  (bytes: !$A.arr(byte, l, size), length: int length, token: string n, n: int n, at: int at, j: int j): bool =
  if j >= n then true
  else if at + j >= length then false
  else if byte2int0($A.get<byte>(bytes, at + j)) <> char2int0(string_get_at(token, j)) then false
  else _starts(bytes, length, token, n, at, j + 1)

fun _find {l:agz}{size:nat}{length:nat | length <= size}{n:nat}{from:nat | from <= length} .<length - from>.
  (bytes: !$A.arr(byte, l, size), length: int length, token: string n, n: int n, from: int from): bool =
  if from >= length then false
  else if _starts(bytes, length, token, n, from, 0) then true
  else _find(bytes, length, token, n, from + 1)

(* Whether the text holds the token *)
fn _has {n:nat} (head: !head, token: string n): bool =
  case+ head of
  | @Head(bytes, length) => let
      val found = _find(bytes, length, token, g1u2i(string1_length(token)), 0)
      prval () = fold@(head)
    in found end
  | NoHead() => false

(* Whether the text is the token, all of it *)
fn _is {n:nat} (head: !head, token: string n): bool =
  case+ head of
  | @Head(bytes, length) => let
      val n = g1u2i(string1_length(token))
      val same = (if length = n then _starts(bytes, length, token, n, 0, 0) else false): bool
      prval () = fold@(head)
    in same end
  | NoHead() => false

(* ---- the engine ---- *)

datatype engine_kind =
  | EkNone
  | EkBlink
  | EkWebKit
  | EkGecko

fn _engine_kind (head: !head): engine_kind =
  if _has(head, "Firefox/") then EkGecko()
  else if _has(head, "CriOS/") || _has(head, "FxiOS/") || _has(head, "EdgiOS/") then EkWebKit()
  else if _has(head, "Chrome/") then EkBlink()
  else if _has(head, "AppleWebKit/") then EkWebKit()
  else EkNone()

fn _read_engine (): engine_reading = let
  val agent = _user_agent()
  val head = _head_of(agent)
  val kind = _engine_kind(head)
  val () = _head_free(head)
in
  case+ kind of
  | EkBlink() => let val () = platform_fact_free(agent) in EngineBlink() end
  | EkWebKit() => let val () = platform_fact_free(agent) in EngineWebKit() end
  | EkGecko() => let val () = platform_fact_free(agent) in EngineGecko() end
  | EkNone() => EngineUnexpected(SourceUserAgent(), agent)
end

(* ---- the operating system ---- *)

datatype os_kind =
  | OkNone
  | OkAndroid
  | OkIos
  | OkIpad
  | OkMac
  | OkWindows
  | OkLinux
  | OkChromeOs
  | OkTouchBad

(* The order matters: Android's text says Linux, an iPhone's says Mac OS X,
   a Chromebook's says X11 *)
fn _os_kind (head: !head): os_kind =
  if _has(head, "Android") then OkAndroid()
  else if _has(head, "iPhone") || _has(head, "iPod") then OkIos()
  else if _has(head, "iPad") then OkIpad()
  else if _has(head, "CrOS") || _has(head, "Chrome OS") then OkChromeOs()
  else if _has(head, "Windows") || _has(head, "Win") then OkWindows()
  else if _has(head, "Mac") || _has(head, "macOS") then OkMac()
  else if _has(head, "Linux") || _has(head, "X11") then OkLinux()
  else OkNone()

fn _os_kind_of (fact: !platform_fact): os_kind = let
  val head = _head_of(fact)
  val kind = _os_kind(head)
  val () = _head_free(head)
in kind end

datatype touch_kind =
  | TouchMany
  | TouchFew
  | TouchAbsent
  | TouchBad

(* The digits of a count, at most 6 of them, else -1 *)
fun _digits {l:agz}{size:nat}{length:nat | length <= size}{at:nat | at <= length} .<length - at>.
  (bytes: !$A.arr(byte, l, size), length: int length, at: int at, value: int): int =
  if at >= length then value
  else if at >= 6 then ~1
  else let
    val c = byte2int0($A.get<byte>(bytes, at))
  in
    if c >= 48 && c <= 57 then _digits(bytes, length, at + 1, value * 10 + (c - 48))
    else ~1
  end

fn _touch_count (head: !head): touch_kind =
  case+ head of
  | @Head(bytes, length) => let
      val count = (if length <= 0 then ~1 else _digits(bytes, length, 0, 0)): int
      prval () = fold@(head)
    in
      if count < 0 then TouchBad()
      else if count > 1 then TouchMany()
      else TouchFew()
    end
  | NoHead() => TouchBad()

fn _touch_of (fact: !platform_fact): touch_kind =
  case+ fact of
  | PlatformFactAbsent() => TouchAbsent()
  | @PlatformFactText(_) => let
      prval () = fold@(fact)
      val head = _head_of(fact)
      val kind = _touch_count(head)
      val () = _head_free(head)
    in kind end
  | @PlatformFactThrew(_) => let prval () = fold@(fact) in TouchBad() end
  | @PlatformFactNotText(_) => let prval () = fold@(fact) in TouchBad() end
  | @PlatformFactCode(_) => let prval () = fold@(fact) in TouchBad() end

fn _read_os (): os_reading = let
  val agent = _user_agent()
  val agent_platform = _user_agent_platform()
  val navigator_platform = _navigator_platform()
  val touch = _touch_points()
  val first = _os_kind_of(agent)
  val second = (case+ first of OkNone() => _os_kind_of(agent_platform) | _ => OkNone()): os_kind
  val third = (case+ second of OkNone() => (case+ first of OkNone() => _os_kind_of(navigator_platform) | _ => OkNone()) | _ => OkNone()): os_kind
  val named = (case+ first of
    | OkNone() => (case+ second of OkNone() => third | _ => second)
    | _ => first): os_kind
  val kind = (case+ named of
    | OkMac() => (case+ _touch_of(touch) of
        | TouchMany() => OkIpad()
        | TouchFew() => OkMac()
        | TouchAbsent() => OkMac()
        | TouchBad() => OkTouchBad())
    | _ => named): os_kind
in
  case+ kind of
  | OkTouchBad() => let
      val () = platform_fact_free(agent)
      val () = platform_fact_free(agent_platform)
      val () = platform_fact_free(navigator_platform)
    in OsUnexpected(SourceTouchPoints(), touch) end
  | OkNone() => let
      val () = platform_fact_free(agent_platform)
      val () = platform_fact_free(navigator_platform)
      val () = platform_fact_free(touch)
    in OsUnexpected(SourceUserAgent(), agent) end
  | _ => let
      val () = platform_fact_free(agent)
      val () = platform_fact_free(agent_platform)
      val () = platform_fact_free(navigator_platform)
      val () = platform_fact_free(touch)
    in
      case+ kind of
      | OkAndroid() => OsAndroid()
      | OkIos() => OsIos()
      | OkIpad() => OsIpadOs()
      | OkMac() => OsMacOs()
      | OkWindows() => OsWindows()
      | OkLinux() => OsLinux()
      | OkChromeOs() => OsChromeOs()
      | OkNone() => OsUnexpected(SourceUserAgent(), PlatformFactAbsent())
      | OkTouchBad() => OsUnexpected(SourceTouchPoints(), PlatformFactAbsent())
    end
end

(* ---- the app shell ---- *)

datatype capacitor_kind =
  | CapNone
  | CapWeb
  | CapIos
  | CapAndroid
  | CapOther

fn _capacitor_kind (fact: !platform_fact): capacitor_kind =
  case+ fact of
  | PlatformFactAbsent() => CapNone()
  | @PlatformFactText(_) => let
      prval () = fold@(fact)
      val head = _head_of(fact)
      val kind = (
        if _is(head, "web") then CapWeb()
        else if _is(head, "ios") then CapIos()
        else if _is(head, "android") then CapAndroid()
        else CapOther()): capacitor_kind
      val () = _head_free(head)
    in kind end
  | @PlatformFactThrew(_) => let prval () = fold@(fact) in CapOther() end
  | @PlatformFactNotText(_) => let prval () = fold@(fact) in CapOther() end
  | @PlatformFactCode(_) => let prval () = fold@(fact) in CapOther() end

(* A WebView's user agent: Android's has "; wv)", an iOS WebView's has
   AppleWebKit/ and no Safari/ *)
fn _webview (head: !head): bool =
  if _has(head, "Android") then _has(head, "; wv)")
  else if _has(head, "iPhone") || _has(head, "iPad") || _has(head, "iPod") then
    (_has(head, "AppleWebKit/") && not(_has(head, "Safari/")))
  else false

fn _read_shell (): shell_reading = let
  val capacitor = _capacitor()
  val agent = _user_agent()
  val head = _head_of(agent)
  val webview = _webview(head)
  val () = _head_free(head)
  val () = platform_fact_free(agent)
  val kind = _capacitor_kind(capacitor)
in
  case+ kind of
  | CapIos() => let val () = platform_fact_free(capacitor) in ShellApp(AppIos()) end
  | CapAndroid() => let val () = platform_fact_free(capacitor) in ShellApp(AppAndroid()) end
  | CapOther() => ShellUnexpected(SourceCapacitor(), capacitor)
  | CapNone() => let val () = platform_fact_free(capacitor) in
      if webview then ShellWebView() else ShellBrowser() end
  | CapWeb() => let val () = platform_fact_free(capacitor) in
      if webview then ShellWebView() else ShellBrowser() end
end

implement platform_read() = PlatformIs(_read_engine(), _read_os(), _read_shell())

implement platform_free(reading) =
  case+ reading of
  | ~PlatformIs(engine, os, shell) => let
      val () = (case+ engine of
        | ~EngineBlink() => ()
        | ~EngineWebKit() => ()
        | ~EngineGecko() => ()
        | ~EngineUnexpected(_, fact) => platform_fact_free(fact))
      val () = (case+ os of
        | ~OsAndroid() => ()
        | ~OsIos() => ()
        | ~OsIpadOs() => ()
        | ~OsMacOs() => ()
        | ~OsWindows() => ()
        | ~OsLinux() => ()
        | ~OsChromeOs() => ()
        | ~OsUnexpected(_, fact) => platform_fact_free(fact))
    in
      case+ shell of
      | ~ShellBrowser() => ()
      | ~ShellApp(_) => ()
      | ~ShellWebView() => ()
      | ~ShellUnexpected(_, fact) => platform_fact_free(fact)
    end

end (* #target wasm *)
