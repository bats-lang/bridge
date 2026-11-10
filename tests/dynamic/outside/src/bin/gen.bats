#target native
#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use file as F
#use result as R
#use wasm.bats-packages.dev/bridge as BR

(* Writes dist/bridge.js with produce_bridge_app_book, the form with the
   book container and the outside reads (pwa has no book form yet) *)
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
  var js = $B.create()
  val () = $BR.produce_bridge_app_book(js, "app.wasm", "bats-root")
in write_js("dist/bridge.js", js) end
