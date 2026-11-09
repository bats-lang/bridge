#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload IE = "wasm.bats-packages.dev/bridge/src/image_error.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"

(* a[0, n) pushed as the page's address, which check.mjs prints *)
fn push_bytes {l:agz}{n:nat} (a: $A.arr(byte, l, n), n: int n): void = let
  val @(frozen, borrowed) = $A.freeze<byte>(a)
  val () = $NAV.push_state(borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn push_text {n:pos | n < 256} (s: string n): void = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in push_bytes(a, n) end

(* Each image that fails to draw: its node id is pushed as the address
   (history.pushState, which check.mjs logs for each call) *)
fn listen (): void =
  $IE.listen_image_error(0, llam(failure) =>
    case+ failure of
    | ~$IE.ImageFailed(id) => let
        val n = $BD.blob_len(id)
      in
        if n > 200 then $BD.blob_free(id)
        else let
          val copy = $A.alloc<byte>(n)
          val () = $BD.blob_read(id, 0, copy, n)
          val () = $BD.blob_free(id)
        in push_bytes(copy, n) end
      end)

implement main0 () = let
  val () = (if $IE.image_error_available() then push_text("available") else push_text("unavailable"))
in listen() end
