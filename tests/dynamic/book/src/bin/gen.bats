#target native
#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use file as F
#use result as R
#use wasm.bats-packages.dev/bridge as BR
#use css as C
staload CB = "css/src/book.sats"

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

(* css's refused table, one entry on each line after the count, for check.mjs to
   compare with the BOOK_REFUSED that bridge.js holds (bridge#267): an entry is at
   most 11 bytes and a newline follows it *)
fun put_entries {cnt:nat | cnt <= 17}{i:nat | i <= cnt}{n:nat | n + 12 * (cnt - i) <= $B.BUILDER_CAP} .<cnt - i>.
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 12 * (cnt - i)] $B.builder(m),
   cnt: int(cnt), i: int(i)): void =
  if i >= cnt then ()
  else let
    val () = $B.bput(b, $CB.book_refused_entry(i))
    val () = $B.put_newline(b)
  in put_entries(b, cnt, i + 1) end

implement main0 () = let
  var js = $B.create()
  val () = $BR.produce_bridge_app_book(js, "app.wasm", "bats-root")
  val () = write_js("dist/bridge.js", js)
  var table = $B.create()
  val () = $B.put_int(table, $CB.book_refused_count ())
  val () = $B.put_newline(table)
  val () = put_entries(table, $CB.book_refused_count (), 0)
in write_js("dist/refused.txt", table) end
