#target native
#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use file as F
#use result as R
#use pwa as P
#use wasm.bats-packages.dev/bridge as BR

(* The old forms of bridge's JS (bridge-js, removal bridge#253), called so
   an edit cannot drop them: pwa's create_pwa calls produce_bridge_app (it
   writes dist/pwa/bridge.js), and this writes dist/pwa/bridge-plain.js with
   produce_bridge, in a builder whose room is the old bound exactly, and
   dist/pwa/bridge-platform.js with produce_bridge_platform, the form with
   the platform atom and without the image error atom (bridge#277) *)
fn write_js {sn:nat | sn < 1000}{m:nat | m <= $B.BUILDER_CAP} (name: string sn, js: $B.builder(m)): void = let
  var path = $B.create()
  val () = $B.bput(path, name)
  val () = $B.put_char(path, 0)
  val @(path_arr, _) = $B.to_arr(path)
  val @(path_fz, path_bv) = $A.freeze<byte>(path_arr)
  val opened = $F.file_open(path_bv, 524288, $F.WriteOnly(), $F.CreateOrTruncate(), 420)
  val () = $A.drop<byte>(path_fz, path_bv)
  val () = $A.free<byte>($A.thaw<byte>(path_fz))
in
  case+ opened of
  | ~$R.ok(fd) => let
      val @(js_arr, js_len) = $B.to_arr(js)
      val @(js_fz, js_bv) = $A.freeze<byte>(js_arr)
    in
      if js_len > 0 then let
          val @(left, right) = $A.borrow_split<byte>(js_fz, js_bv, js_len)
          val () = $R.discard<int><$F.io_error>((case+ $F.file_write(fd, left, js_len) of
            | ~$R.ok(w) => $R.ok(w) | ~$R.err(e) => $R.err(e)): $R.result(int, $F.io_error))
          val () = $A.drop<byte>(js_fz, $A.borrow_join<byte>(js_fz, left, right))
          val () = $A.free<byte>($A.thaw<byte>(js_fz))
        in $R.discard<int><$F.io_error>($F.file_close(fd)) end
      else let
          val () = $A.drop<byte>(js_fz, js_bv)
          val () = $A.free<byte>($A.thaw<byte>(js_fz))
        in $R.discard<int><$F.io_error>($F.file_close(fd)) end
    end
  | ~$R.err(_) => $B.builder_free(js)
end

implement main0 () = let
  val assets = $A.alloc<byte>(1)
  val () = $P.create_pwa("Old bridge", "dev.bats.old-bridge",
    "dist/debug/app.wasm", "app.wasm", "dist/pwa",
    assets, 0, 1)
  val () = $A.free<byte>(assets)
  var plain = $B.create()
  val () = $BR.produce_bridge(plain)
  val () = write_js("dist/pwa/bridge-plain.js", plain)
  var platform = $B.create()
  val () = $BR.produce_bridge_platform(platform)
in write_js("dist/pwa/bridge-platform.js", platform) end
