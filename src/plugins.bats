(* plugins -- the Capacitor plugins bridge's atoms use in the native app

   Bridge's atoms reach the app's native features through
   Capacitor.Plugins[name], each behind its *_available check. This is
   the one table of those plugins: what the atoms call them (the name the
   JS reaches them by) and what the app installs for them (the npm
   package and its version range). The JS gets a plugin's name only
   from here (put_plugin_call), so an atom cannot use a plugin the table
   does not have; pwa's Android generator writes the app's package.json
   from it (put_plugin_dependencies), so the app has every plugin an atom
   may use. Every app gets every plugin for now; a selection would be a
   predicate over plugin, with no change to the atoms. *)

#include "share/atspre_staload.hats"

#use builder as B

(* ============================================================
   The table
   ============================================================ *)

#pub datatype plugin =
  (* The status bar hidden for full screen (screen.bats) *)
  | PluginStatusBar
  (* The rotation locked (screen.bats) *)
  | PluginScreenOrientation
  (* The screen's brightness (screen.bats) *)
  | PluginScreenBrightness
  (* Sharing text and files (share.bats) *)
  | PluginShare
  (* Files in the app's own directories: a file shared is written to its
     cache first (share.bats) *)
  | PluginFilesystem
  (* A Google access token for the account on the device *)
  | PluginGoogleSignIn
  (* An address opened in the system browser's tab over the app (a
     Custom Tab on Android), as an OAuth sign-in is (browser_tab.bats) *)
  | PluginBrowser
  (* The addresses the app is opened at, its own scheme's: an OAuth
     sign-in coming back (app_link.bats) *)
  | PluginApp

#pub stadef PLUGIN_COUNT = 8

(* The i-th plugin of the table, for walking it *)
#pub fn plugin_at {i:nat | i < PLUGIN_COUNT} (i: int i): plugin

(* The name the JS reaches it by, Capacitor.Plugins[name] *)
#pub fn plugin_name (p: plugin): [s:pos | s <= 24] string s

(* The npm package the app installs for it *)
#pub fn plugin_package (p: plugin): [s:pos | s <= 48] string s

(* The package's version range *)
#pub fn plugin_version (p: plugin): [s:pos | s <= 16] string s

implement plugin_at (i) =
  if i = 0 then PluginStatusBar
  else if i = 1 then PluginScreenOrientation
  else if i = 2 then PluginScreenBrightness
  else if i = 3 then PluginShare
  else if i = 4 then PluginFilesystem
  else if i = 5 then PluginGoogleSignIn
  else if i = 6 then PluginBrowser
  else PluginApp

implement plugin_name (p) =
  case+ p of
  | PluginStatusBar() => "StatusBar"
  | PluginScreenOrientation() => "ScreenOrientation"
  | PluginScreenBrightness() => "ScreenBrightness"
  | PluginShare() => "Share"
  | PluginFilesystem() => "Filesystem"
  | PluginGoogleSignIn() => "GoogleSignIn"
  | PluginBrowser() => "Browser"
  | PluginApp() => "App"

implement plugin_package (p) =
  case+ p of
  | PluginStatusBar() => "@capacitor/status-bar"
  | PluginScreenOrientation() => "@capacitor/screen-orientation"
  | PluginScreenBrightness() => "@capacitor-community/screen-brightness"
  | PluginShare() => "@capacitor/share"
  | PluginFilesystem() => "@capacitor/filesystem"
  | PluginGoogleSignIn() => "@capawesome/capacitor-google-sign-in"
  | PluginBrowser() => "@capacitor/browser"
  | PluginApp() => "@capacitor/app"

implement plugin_version (p) =
  case+ p of
  | PluginStatusBar() => "^8.0.4"
  | PluginScreenOrientation() => "^8.0.2"
  | PluginScreenBrightness() => "^8.0.0"
  | PluginShare() => "^8.0.3"
  | PluginFilesystem() => "^8.1.3"
  | PluginGoogleSignIn() => "^0.1.4"
  | PluginBrowser() => "^8.0.5"
  | PluginApp() => "^8.1.2"

(* The Kotlin standard library the app needs: the newest any plugin's
   Android code is compiled with (Filesystem 8.1.3's, 2.2.20; the others
   are Java, Browser's and App's too). An older one the app forces makes a plugin's code fail as
   it runs, missing a class of the newer library (SpillingKt, quire#223).
   A plugin added or updated here that is compiled with a newer Kotlin
   moves it *)
#pub fn plugins_kotlin (): [s:pos | s <= 16] string s

implement plugins_kotlin () = "2.2.20"

(* ============================================================
   Writing it out
   ============================================================ *)

(* capPlugin('<name>'): the JS's plugin of that name, or null where the
   app does not run natively with it *)
#pub fn put_plugin_call {n:nat | n + 40 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 40] $B.builder(m), p: plugin): void

implement put_plugin_call (b, p) = let
  val () = $B.bput(b, "capPlugin('")
  val () = $B.bput(b, plugin_name(p))
in $B.bput(b, "')") end

(* ",\n" when sep *)
fn put_separator {n:nat | n + 2 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 2] $B.builder(m), sep: bool): void =
  if sep then $B.bput(b, ",\n") else ()

(* "<package>": "<version>", one line, after ",\n" when sep *)
fn put_dependency {n:nat | n + 80 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 80] $B.builder(m),
   p: plugin, indent: [s:nat | s <= 8] string s, sep: bool): void = let
  val () = put_separator(b, sep)
  val () = $B.bput(b, indent)
  val () = $B.bput(b, "\"")
  val () = $B.bput(b, plugin_package(p))
  val () = $B.bput(b, "\": \"")
  val () = $B.bput(b, plugin_version(p))
in $B.bput(b, "\"") end

fun put_dependencies_from {i:nat | i <= PLUGIN_COUNT}{n:nat | n + 80 * (PLUGIN_COUNT - i) <= $B.BUILDER_CAP} .<PLUGIN_COUNT - i>.
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 80 * (PLUGIN_COUNT - i)] $B.builder(m),
   i: int i, indent: [s:nat | s <= 8] string s, sep: bool): void =
  if i >= 8 then ()
  else let
    val () = put_dependency(b, plugin_at(i), indent, sep)
  in put_dependencies_from(b, i + 1, indent, true) end

(* Each plugin's package as a package.json dependency, "<package>":
   "<version>", each line after indent and all but the last ending in a
   comma; no newline after the last *)
#pub fn put_plugin_dependencies {n:nat | n + 640 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 640] $B.builder(m),
   indent: [s:nat | s <= 8] string s): void

implement put_plugin_dependencies (b, indent) =
  put_dependencies_from(b, 0, indent, false)
