#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload AL = "wasm.bats-packages.dev/bridge/src/app_link.bats"

(* Answers nobody took, freed: before their first use *)
implement $P.dispose<$AL.tab_opened>(_) = ()

(* s's bytes in a fresh array of exactly its length *)
fn bytes {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

(* Opens a[0, n) in a browser tab *)
fn open_bytes {l:agz}{n:nat} (a: $A.arr(byte, l, n), n: int n): $P.promise($AL.tab_opened, $P.Chained) = let
  val @(frozen, borrowed) = $A.freeze<byte>(a)
  val opened = $AL.browser_tab_open(borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in opened end

fn open_text {n:pos | n < 256} (s: string n): $P.promise($AL.tab_opened, $P.Chained) =
  open_bytes(bytes(s), g1u2i(string1_length(s)))

(* How a tab opened, told by the address opened next *)
fn told (opened: $AL.tab_opened): $P.promise($AL.tab_opened, $P.Chained) =
  case+ opened of
  | $AL.TabOpened() => open_text("https://example.com/opened")
  | $AL.TabNotOpened() => open_text("https://example.com/not-opened")

(* check.mjs plays the app's Browser and App: each address the app is
   opened at closes the tab and is opened again (shown only when it is
   https); a tab is opened, and one at an http address is refused *)
implement main0 () =
  if ~$AL.browser_tab_available() then ()
  else let
    val () = $AL.listen_app_link(0, llam(link) => let
        val n = $BD.blob_len(link)
        val () = $AL.browser_tab_close()
      in
        if n > 4096 then $BD.blob_free(link)
        else let
          val copy = $A.alloc<byte>(n)
          val () = $BD.blob_read(link, 0, copy, n)
          val () = $BD.blob_free(link)
        in $P.finish<$AL.tab_opened>(open_bytes(copy, n), llam(_) => ()) end
      end)
    val first = $P.and_then<$AL.tab_opened><$AL.tab_opened>(open_text("https://example.com/sign-in"), llam(opened) => told(opened))
    val second = $P.and_then<$AL.tab_opened><$AL.tab_opened>(first, llam(_) => open_text("http://example.com/plain"))
    val third = $P.and_then<$AL.tab_opened><$AL.tab_opened>(second, llam(opened) => told(opened))
  in $P.finish<$AL.tab_opened>(third, llam(_) => ()) end
