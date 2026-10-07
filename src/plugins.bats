(* plugins -- the Capacitor plugins bridge's atoms use in the native app

   Bridge's atoms reach the app's native features through
   Capacitor.Plugins[name], each behind its *_available check. This is
   the one table of those plugins: what the atoms call them (the name the
   JS reaches them by) and what the app installs for them (the npm
   package, and where it comes from: a version range of the registry's,
   or a commit of a git repository's, plugin_source), or that
   Capacitor's Android runtime has it itself (plugin_origin), so the app
   installs nothing for it. The JS gets a plugin's name only
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

(* A plugin's index says whether its package comes from a git
   repository (1) or not (0): the package.json line of one from git is
   longer, and its index is what lets the table's lines be counted in
   their bound (put_plugin_dependencies) *)
#pub datatype plugin(git:int) =
  (* The system bars, the status bar and the navigation bar, hidden
     together for full screen (screen.bats): Capacitor's own, in
     @capacitor/android since 8 *)
  | PluginSystemBars(0)
  (* The rotation locked (screen.bats) *)
  | PluginScreenOrientation(0)
  (* The screen's brightness (screen.bats) *)
  | PluginScreenBrightness(0)
  (* Sharing text and files (share.bats) *)
  | PluginShare(0)
  (* Files in the app's own directories: a file shared is written to its
     cache first (share.bats) *)
  | PluginFilesystem(0)
  (* An address opened in the system browser's tab over the app (a
     Custom Tab on Android), as an OAuth sign-in is (browser_tab.bats) *)
  | PluginBrowser(0)
  (* The addresses the app is opened at, its own scheme's: an OAuth
     sign-in coming back (app_link.bats); Android's Back, and the app
     moved to the background (back_button.bats) *)
  | PluginApp(0)
  (* Google authorization with no sign-in, Play services'
     AuthorizationClient (google_authorize.bats): bats-lang's own,
     bats-lang/capacitor-plugins' google-authorize *)
  | PluginGoogleAuthorize(1)

#pub stadef PLUGIN_COUNT = 8

(* Whether the table's i-th plugin comes from a git repository (1) or
   not (0), and how many of the table's plugins from the i-th on do:
   plugin_at's index, kept with the table *)
#pub stadef GIT_AT(i:int) = ifint(i == 7, 1, 0)
#pub stadef GIT_FROM(i:int) = ifint(i <= 7, 1, 0)

(* The i-th plugin of the table, for walking it *)
#pub fn plugin_at {i:nat | i < PLUGIN_COUNT} (i: int i): plugin(GIT_AT(i))

(* The name the JS reaches it by, Capacitor.Plugins[name] *)
#pub fn plugin_name {g:int} (p: plugin(g)): [s:pos | s <= 24] string s

(* Where the app gets a plugin: Capacitor's Android runtime has it
   (CapacitorCore: the app's package.json names @capacitor/android
   anyway, so the plugin is not a dependency of its own), or its own npm
   package (Package) *)
#pub datatype plugin_origin = CapacitorCore | Package

#pub fn plugin_origin {g:int} (p: plugin(g)): plugin_origin

implement plugin_origin (p) =
  case+ p of
  | PluginSystemBars() => CapacitorCore()
  | PluginScreenOrientation() => Package()
  | PluginScreenBrightness() => Package()
  | PluginShare() => Package()
  | PluginFilesystem() => Package()
  | PluginBrowser() => Package()
  | PluginApp() => Package()
  | PluginGoogleAuthorize() => Package()

(* The npm package the app installs for it (Capacitor's runtime, for a
   CapacitorCore plugin): its name, as package.json names it *)
#pub fn plugin_package {g:int} (p: plugin(g)): [s:pos | s <= 40] string s

(* Where the package comes from, as package.json's value for it says
   (https://docs.npmjs.com/cli/v11/configuring-npm/package-json#dependencies,
   https://pnpm.io/package-sources). Its index is the plugin's: 1 for a
   git repository's. Linear, as a constructor that carries data is: the
   match that reads it frees it *)
#pub datavtype plugin_source(git:int) =
  (* The registry's, a version range: "^8.1.0" *)
  | Registry(0) of ([s:pos | s <= 7] string s)
  (* A git repository's, on GitHub: the repository ("owner/name"), the
     full commit (40 hexadecimal digits) and the package's directory in
     it ("/packages/name"), "github:<repository>#<commit>&path:<path>".
     pnpm installs a package from a directory of a repository, which npm
     cannot (bats-lang/quire#321), so an app with one is installed by
     pnpm *)
  | Git(1) of ([s:pos | s <= 28] string s, string 40, [s:pos | s <= 28] string s)

#pub fn plugin_source {g:int} (p: plugin(g)): plugin_source(g)

implement plugin_at (i) =
  if i = 0 then PluginSystemBars
  else if i = 1 then PluginScreenOrientation
  else if i = 2 then PluginScreenBrightness
  else if i = 3 then PluginShare
  else if i = 4 then PluginFilesystem
  else if i = 5 then PluginBrowser
  else if i = 6 then PluginApp
  else PluginGoogleAuthorize

implement plugin_name (p) =
  case+ p of
  | PluginSystemBars() => "SystemBars"
  | PluginScreenOrientation() => "ScreenOrientation"
  | PluginScreenBrightness() => "ScreenBrightness"
  | PluginShare() => "Share"
  | PluginFilesystem() => "Filesystem"
  | PluginBrowser() => "Browser"
  | PluginApp() => "App"
  | PluginGoogleAuthorize() => "GoogleAuthorize"

implement plugin_package (p) =
  case+ p of
  | PluginSystemBars() => "@capacitor/android"
  | PluginScreenOrientation() => "@capacitor/screen-orientation"
  | PluginScreenBrightness() => "@capacitor-community/screen-brightness"
  | PluginShare() => "@capacitor/share"
  | PluginFilesystem() => "@capacitor/filesystem"
  | PluginBrowser() => "@capacitor/browser"
  | PluginApp() => "@capacitor/app"
  | PluginGoogleAuthorize() => "@bats-lang/capacitor-google-authorize"

implement plugin_source (p) =
  case+ p of
  | PluginSystemBars() => Registry("^8.1.0")
  | PluginScreenOrientation() => Registry("^8.0.2")
  | PluginScreenBrightness() => Registry("^8.0.0")
  | PluginShare() => Registry("^8.0.3")
  | PluginFilesystem() => Registry("^8.1.3")
  | PluginBrowser() => Registry("^8.0.5")
  | PluginApp() => Registry("^8.1.2")
  (* capacitor-plugins' main after its #6 (quire#334) *)
  | PluginGoogleAuthorize() => Git("bats-lang/capacitor-plugins",
      "0c5fa45f7a38a8bbce1645c912e5a81a2e495735", "/packages/google-authorize")

(* The Kotlin standard library the app needs: the newest any plugin's
   Android code is compiled with (Filesystem 8.1.3's, 2.2.20; the others
   are Java, Browser's, App's and GoogleAuthorize's too). An older one the app forces makes a plugin's code fail as
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
#pub fn put_plugin_call {g:int}{n:nat | n + 40 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 40] $B.builder(m), p: plugin(g)): void

implement put_plugin_call (b, p) = let
  val () = $B.bput(b, "capPlugin('")
  val () = $B.bput(b, plugin_name(p))
in $B.bput(b, "')") end

(* ",\n" when sep *)
fn put_separator {n:nat | n + 2 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 2] $B.builder(m), sep: bool): void =
  if sep then $B.bput(b, ",\n") else ()

(* The longest line of a package.json dependency, ",\n" and the indent
   included: a registry's ("<package>": "<range>") and, longer by
   GIT_LONGER, a git repository's ("<package>": "github:<repository>#
   <commit>&path:<path>") *)
stadef LINE_MOST = 2 + 4 + 1 + 40 + 4 + 7 + 1
stadef GIT_LONGER = (7 + 28 + 1 + 40 + 6 + 28) - 7

(* package.json's value for the source, without its quotes *)
fn put_source {g:nat | g <= 1}{n:nat | n + 7 + GIT_LONGER <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 7 + GIT_LONGER * g] $B.builder(m),
   source: plugin_source(g)): void =
  case+ source of
  | ~Registry(range) => $B.bput(b, range)
  | ~Git(repository, commit, path) => let
      val () = $B.bput(b, "github:")
      val () = $B.bput(b, repository)
      val () = $B.bput(b, "#")
      val () = $B.bput(b, commit)
      val () = $B.bput(b, "&path:")
    in $B.bput(b, path) end

(* "<package>": "<source>", one line, after ",\n" when sep *)
fn put_dependency {g:nat | g <= 1}{n:nat | n + LINE_MOST + GIT_LONGER <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + LINE_MOST + GIT_LONGER * g] $B.builder(m),
   p: plugin(g), indent: [s:nat | s <= 4] string s, sep: bool): void = let
  val () = put_separator(b, sep)
  val () = $B.bput(b, indent)
  val () = $B.bput(b, "\"")
  val () = $B.bput(b, plugin_package(p))
  val () = $B.bput(b, "\": \"")
  val () = put_source(b, plugin_source(p))
in $B.bput(b, "\"") end

(* The longest the lines of the table's plugins from the i-th on can be *)
stadef LINES_FROM(i:int) = LINE_MOST * (PLUGIN_COUNT - i) + GIT_LONGER * GIT_FROM(i)

fun put_dependencies_from {i:nat | i <= PLUGIN_COUNT}{n:nat | n + LINES_FROM(i) <= $B.BUILDER_CAP} .<PLUGIN_COUNT - i>.
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + LINES_FROM(i)] $B.builder(m),
   i: int i, indent: [s:nat | s <= 4] string s, sep: bool): void =
  if i >= 8 then ()
  else let
    val p = plugin_at(i)
  in
    case+ plugin_origin(p) of
    | CapacitorCore() => put_dependencies_from(b, i + 1, indent, sep)
    | Package() => let
        val () = put_dependency(b, p, indent, sep)
      in put_dependencies_from(b, i + 1, indent, true) end
  end

(* Each plugin's package as a package.json dependency (a CapacitorCore
   plugin has none of its own), "<package>": "<source>", each line after
   indent and all but the last ending in a comma; no newline after the
   last *)
#pub fn put_plugin_dependencies {n:nat | n + 640 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 640] $B.builder(m),
   indent: [s:nat | s <= 4] string s): void

implement put_plugin_dependencies (b, indent) =
  put_dependencies_from(b, 0, indent, false)
