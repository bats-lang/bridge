#target native
#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use file as F
#use result as R
#use pwa as P
#use wasm.bats-packages.dev/bridge as BR

(* Writes dist/pwa/ with pwa (index.html, app.wasm, ...), then replaces its
   bridge.js with the bridge that has the platform atom: pwa calls
   produce_bridge_app, the form without it (bridge#191, removal bridge#253),
   so the test generates the bridge with produce_bridge_app_platform itself *)
fn write_bridge (): void = let
  var path = $B.create()
  val () = $B.bput(path, "dist/pwa/bridge.js")
  val () = $B.put_char(path, 0)
  val @(path_arr, _) = $B.to_arr(path)
  val @(path_fz, path_bv) = $A.freeze<byte>(path_arr)
  val opened = $F.file_open(path_bv, 524288, $F.WriteOnly(), $F.CreateOrTruncate(), 420)
  val () = $A.drop<byte>(path_fz, path_bv)
  val () = $A.free<byte>($A.thaw<byte>(path_fz))
in
  case+ opened of
  | ~$R.ok(fd) => let
      var js = $B.create()
      val () = $BR.produce_bridge_app_platform(js, "app.wasm", "bats-root")
      val @(js_arr, js_len) = $B.to_arr(js)
      val @(js_fz, js_bv) = $A.freeze<byte>(js_arr)
      val () = (if js_len > 0 then let
          val @(left, right) = $A.borrow_split<byte>(js_fz, js_bv, js_len)
          val () = $R.discard<int><$F.io_error>((case+ $F.file_write(fd, left, js_len) of
            | ~$R.ok(w) => $R.ok(w) | ~$R.err(e) => $R.err(e)): $R.result(int, $F.io_error))
          val () = $A.drop<byte>(js_fz, $A.borrow_join<byte>(js_fz, left, right))
        in () end
        else $A.drop<byte>(js_fz, js_bv))
      val () = $A.free<byte>($A.thaw<byte>(js_fz))
    in $R.discard<int><$F.io_error>($F.file_close(fd)) end
  | ~$R.err(_) => ()
end

implement main0 () = let
  val assets = $A.alloc<byte>(1)
  val () = $P.create_pwa("Platform read", "dev.bats.platform-read",
    "dist/debug/app.wasm", "app.wasm", "dist/pwa",
    assets, 0, 1)
  val () = $A.free<byte>(assets)
in write_bridge() end
