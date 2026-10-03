#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload BT = "wasm.bats-packages.dev/bridge/src/browser_tab.bats"
staload AL = "wasm.bats-packages.dev/bridge/src/app_link.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"

(* Answers nobody took, freed: before their first use *)
implement $P.dispose<$BT.tab_opened>(_) = ()

(* s's bytes in a fresh array of exactly its length *)
fn bytes {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

(* Opens a[0, n) in a browser tab *)
fn open_bytes {l:agz}{n:nat} (a: $A.arr(byte, l, n), n: int n): $P.promise($BT.tab_opened, $P.Chained) = let
  val @(frozen, borrowed) = $A.freeze<byte>(a)
  val opened = $BT.browser_tab_open(borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in opened end

fn open_text {n:pos | n < 256} (s: string n): $P.promise($BT.tab_opened, $P.Chained) =
  open_bytes(bytes(s), g1u2i(string1_length(s)))

(* The page's hash set to a[0, n), which check.mjs prints *)
fn hash_bytes {l:agz}{n:nat} (a: $A.arr(byte, l, n), n: int n): void = let
  val @(frozen, borrowed) = $A.freeze<byte>(a)
  val () = $NAV.set_hash(borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn hash_text {n:pos | n < 256} (s: string n): void =
  hash_bytes(bytes(s), g1u2i(string1_length(s)))

(* How a tab opened, told by the address opened next *)
fn told (opened: $BT.tab_opened): $P.promise($BT.tab_opened, $P.Chained) =
  case+ opened of
  | $BT.TabOpened() => open_text("https://example.com/opened")
  | $BT.TabNotOpened() => open_text("https://example.com/not-opened")

(* Each address the app is opened at, put in the hash *)
fn listen (): void =
  $AL.listen_app_link(0, llam(link) => let
      val n = $BD.blob_len(link)
    in
      if n > 4096 then $BD.blob_free(link)
      else let
        val copy = $A.alloc<byte>(n)
        val () = $BD.blob_read(link, 0, copy, n)
        val () = $BD.blob_free(link)
      in hash_bytes(copy, n) end
    end)

(* How a tab opened, put in the hash (where no Browser plugin prints it) *)
fn told_hash (opened: $BT.tab_opened): void =
  case+ opened of
  | $BT.TabOpened() => hash_text("tab-opened")
  | $BT.TabNotOpened() => hash_text("tab-not-opened")

(* check.mjs plays the native app with its Browser plugin, its App
   plugin, both, or neither (a browser): each one's availability is put
   in the hash, and both atoms are used whatever it says. A tab is
   opened, one at an http address is refused (before JS), and one that
   Browser.open rejects is not opened; with no Browser, the tab not
   opened is put in the hash. Each address the app is opened at is put
   in the hash (with no App, none comes) *)
implement main0 () = let
  val tab = $BT.browser_tab_available()
  val link = $AL.app_link_available()
  val () = (if tab then (if link then hash_text("tab+link") else hash_text("tab"))
    else (if link then hash_text("link") else hash_text("none")))
  val () = listen()
in
  if ~tab then
    $P.finish<$BT.tab_opened>(open_text("https://example.com/sign-in"), llam(opened) => told_hash(opened))
  else let
    val first = $P.and_then<$BT.tab_opened><$BT.tab_opened>(open_text("https://example.com/sign-in"), llam(opened) => told(opened))
    val second = $P.and_then<$BT.tab_opened><$BT.tab_opened>(first, llam(_) => open_text("http://example.com/plain"))
    val third = $P.and_then<$BT.tab_opened><$BT.tab_opened>(second, llam(opened) => told(opened))
    val fourth = $P.and_then<$BT.tab_opened><$BT.tab_opened>(third, llam(_) => open_text("https://example.com/rejected"))
    val fifth = $P.and_then<$BT.tab_opened><$BT.tab_opened>(fourth, llam(opened) => told(opened))
  in $P.finish<$BT.tab_opened>(fifth, llam(_) => ()) end
end
