#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"
staload PL = "wasm.bats-packages.dev/bridge/src/platform.bats"

(* Reads the platform and says every part of the reading in the address's
   hash, a line each: check.mjs prints each hash. The reading is matched with
   case+, every constructor of the engine, the system and the shell visible,
   and every form of a fact (the one an Unexpected keeps). *)

fn say {l:agz}{n:pos | n <= 4096} (a: $A.arr(byte, l, n), n: int n): void = let
  val @(frozen, borrowed) = $A.freeze<byte>(a)
  val () = $NAV.set_hash(borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn say_text {n:pos | n < 256} (s: string n): void = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in say(a, n) end

(* A blob's bytes, as the next hash; "no bytes" for an empty one, "long text"
   for one over 4096 bytes *)
fn say_blob {n:nat} (blob: !$BD.dblob(n)): void = let
  val n = $BD.blob_len(blob)
in
  if n <= 0 then say_text("no bytes")
  else if n > 4096 then say_text("long text")
  else let
    val a = $A.alloc<byte>(n)
    val () = $BD.blob_read(blob, 0, a, n)
  in say(a, n) end
end

fn say_kept (text: $R.option([n:nat] $BD.dblob(n))): void =
  case+ text of
  | ~$R.some(blob) => let val () = say_blob(blob) in $BD.blob_free(blob) end
  | ~$R.none() => say_text("no text")

fn say_fact (fact: $PL.platform_fact): void =
  case+ fact of
  | ~$PL.PlatformFactText(blob) => let
      val () = say_text("text")
      val () = say_blob(blob)
    in $BD.blob_free(blob) end
  | ~$PL.PlatformFactAbsent() => say_text("absent")
  | ~$PL.PlatformFactThrew(text) => let val () = say_text("threw") in say_kept(text) end
  | ~$PL.PlatformFactNotText(text) => let val () = say_text("not text") in say_kept(text) end
  | ~$PL.PlatformFactCode(_) => say_text("code JS never gives")

fn say_source (source: $PL.platform_source): void =
  case+ source of
  | $PL.SourceUserAgent() => say_text("from the user agent")
  | $PL.SourceUserAgentPlatform() => say_text("from userAgentData.platform")
  | $PL.SourceNavigatorPlatform() => say_text("from navigator.platform")
  | $PL.SourceTouchPoints() => say_text("from maxTouchPoints")
  | $PL.SourceCapacitor() => say_text("from Capacitor")

fn say_engine (engine: $PL.engine_reading): void =
  case+ engine of
  | ~$PL.EngineBlink() => say_text("engine: Blink")
  | ~$PL.EngineWebKit() => say_text("engine: WebKit")
  | ~$PL.EngineGecko() => say_text("engine: Gecko")
  | ~$PL.EngineUnexpected(source, fact) => let
      val () = say_text("engine: unexpected")
      val () = say_source(source)
    in say_fact(fact) end

fn say_os (os: $PL.os_reading): void =
  case+ os of
  | ~$PL.OsAndroid() => say_text("os: Android")
  | ~$PL.OsIos() => say_text("os: iOS")
  | ~$PL.OsIpadOs() => say_text("os: iPadOS")
  | ~$PL.OsMacOs() => say_text("os: macOS")
  | ~$PL.OsWindows() => say_text("os: Windows")
  | ~$PL.OsLinux() => say_text("os: Linux")
  | ~$PL.OsChromeOs() => say_text("os: ChromeOS")
  | ~$PL.OsUnexpected(source, fact) => let
      val () = say_text("os: unexpected")
      val () = say_source(source)
    in say_fact(fact) end

fn say_shell (shell: $PL.shell_reading): void =
  case+ shell of
  | ~$PL.ShellBrowser() => say_text("shell: browser")
  | ~$PL.ShellApp(system) => (case+ system of
    | $PL.AppIos() => say_text("shell: app on iOS")
    | $PL.AppAndroid() => say_text("shell: app on Android"))
  | ~$PL.ShellWebView() => say_text("shell: WebView")
  | ~$PL.ShellUnexpected(source, fact) => let
      val () = say_text("shell: unexpected")
      val () = say_source(source)
    in say_fact(fact) end

implement main0 () = let
  val () = (if $PL.platform_available() then say_text("available") else say_text("not available"))
in
  case+ $PL.platform_read() of
  | ~$PL.PlatformIs(engine, os, shell) => let
      val () = say_engine(engine)
      val () = say_os(os)
    in say_shell(shell) end
end
