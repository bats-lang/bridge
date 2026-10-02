(* build_watch -- telling the app a new build of it is served, for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"
staload "./fetch.bats"
staload "./timer.bats"
staload "./window.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* What watching the build found. The app decides what to do with a new
   build: reload at once (nav's reload), or wait for a moment that loses
   nothing (the end of a chapter, say). *)
#pub datatype build_change =
  | NewBuild     (* the build served now is not the one that was loaded *)
  | WatchEnded   (* the server gives the build no ETag or Last-Modified,
                    or a million checks were made: it is asked no more *)

(* Watches the build at url (the app's wasm): its stamp (ETag, else
   Last-Modified) is read now, then again every 30 seconds while the
   page is shown (a check that comes while it is hidden waits until it
   is shown again); the promise resolves the first time the stamp
   differs. A failed check is tried again 30 seconds later. It is asked
   at most a million times (about a year of 30 seconds). *)
#pub fun build_watch
  {lu:agz}{nu:pos | nu < 1024}
  (url: !$A.borrow(byte, lu, nu), url_len: int nu): $P.promise(build_change, $P.Chained)

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

(* How long between checks, in milliseconds *)
#define CHECK_EVERY 30000

(* How many checks a watch makes at most *)
#define CHECKS 1000000

(* A stamp is at most this long *)
#define STAMP_SIZE 256

(* A change nobody took: nothing to free. Before build_watch, its first
   use. *)
implement $P.dispose<build_change>(_) = ()

(* A stamp nobody took: freed *)
datavtype stamp =
  | {l:agz}{k:nat | k <= STAMP_SIZE} Stamp of ($A.arr(byte, l, STAMP_SIZE), int k)
  | Unstamped

implement $P.dispose<stamp>(found) =
  case+ found of
  | ~Stamp(bytes, _) => $A.free<byte>(bytes)
  | ~Unstamped() => ()

(* The value of header name in a response, its length; 0 when it has
   none *)
fn _header {n:pos | n < 64}{l:agz}
  (r: !response, name: string n, out: !$A.arr(byte, l, STAMP_SIZE)): [k:nat | k <= STAMP_SIZE] int k = let
  val name_len = g1u2i(string1_length(name))
  val name_bytes = $A.alloc<byte>(name_len)
  val () = $A.write_text(name_bytes, 0, $A.text_lit(name), name_len)
  val @(name_frozen, name_borrow) = $A.freeze<byte>(name_bytes)
  val found = fetch_header(r, name_borrow, name_len, out, STAMP_SIZE)
  val k = (case+ found of ~$R.some(k) => k | ~$R.none() => 0): [k:nat | k <= STAMP_SIZE] int k
  val () = $A.drop<byte>(name_frozen, name_borrow)
  val () = $A.free<byte>($A.thaw<byte>(name_frozen))
in k end

(* The stamp out[0, k) of a response, when it was answered (ok) and has
   one *)
fn _stamp_of {l:agz}{k:nat | k <= STAMP_SIZE}
  (out: $A.arr(byte, l, STAMP_SIZE), k: int k, ok: bool): stamp =
  if ok && k > 0 then Stamp(out, k)
  else let val () = $A.free<byte>(out) in Unstamped() end

(* The response's ETag in out, else its Last-Modified: its length, 0
   when it has neither *)
fn _stamp_header {l:agz} (r: !response, out: !$A.arr(byte, l, STAMP_SIZE)): [k:nat | k <= STAMP_SIZE] int k = let
  val etag_len = _header(r, "etag", out)
in if etag_len > 0 then etag_len else _header(r, "last-modified", out) end

(* The stamp of what a request came to: a response's, when it was a
   success and has one; its body is let go *)
fn _stamp_of_response (got: fetched): stamp =
  case+ got of
  | ~NoResponse() => Unstamped()
  | ~Responded(r) => let
      val out = $A.alloc<byte>(STAMP_SIZE)
      val k = _stamp_header(r, out)
      val status = fetch_status(r)
      val () = blob_free(fetch_body(r))
    in _stamp_of(out, k, status >= 200 && status < 300) end

(* The build's stamp: a HEAD request for url, not cached *)
fn _stamp_read {lu:agz}{nu:pos} (url: !$A.borrow(byte, lu, nu), url_len: int nu): $P.promise(stamp, $P.Chained) = let
  val method = $A.alloc<byte>(4)
  val () = $A.write_text(method, 0, $A.text_lit("HEAD"), 4)
  val @(method_frozen, method_borrow) = $A.freeze<byte>(method)
  val @(none_frozen, none) = $A.freeze<byte>($A.alloc<byte>(1))
  val body = $A.dup<byte>(none_frozen, none)
  val asked = fetch_request(method_borrow, 4, url, url_len, none, 0, body, 0)
  val () = $A.drop<byte>(none_frozen, body)
  val () = $A.drop<byte>(none_frozen, none)
  val () = $A.free<byte>($A.thaw<byte>(none_frozen))
  val () = $A.drop<byte>(method_frozen, method_borrow)
  val () = $A.free<byte>($A.thaw<byte>(method_frozen))
in $P.and_then<fetched><stamp>(asked, llam (got) => $P.ret<stamp>(_stamp_of_response(got))) end

(* Whether a[0, k) and b[0, k) are the same bytes *)
fun _same {la,lb:agz}{k:nat | k <= STAMP_SIZE}{i:nat | i <= k} .<k - i>.
  (a: !$A.arr(byte, la, STAMP_SIZE), b: !$A.arr(byte, lb, STAMP_SIZE), k: int k, i: int i): bool =
  if i >= k then true
  else if byte2int0($A.get<byte>(a, i)) <> byte2int0($A.get<byte>(b, i)) then false
  else _same(a, b, k, i + 1)

(* The checks after the first. Each waits 30 seconds (waited false),
   then until the page is shown (waited true), then reads the stamp and
   compares it with the first; a different one answers NewBuild. The
   watch's url and first stamp are moved from check to check, and each
   step uses one of the checks left *)
fun _check {lu:agz}{nu:pos}{ls:agz}{ks:pos | ks <= STAMP_SIZE}{checks:nat} .<checks>.
  (checks: int checks, waited: bool, url: $A.arr(byte, lu, nu), url_len: int nu,
   first: $A.arr(byte, ls, STAMP_SIZE), first_len: int ks, answer: $P.resolver(build_change)): void =
  if checks <= 0 then let
    val () = $A.free<byte>(url)
    val () = $A.free<byte>(first)
  in $P.resolve<build_change>(answer, WatchEnded()) end
  else if not(waited) then
    $P.finish<Int>($P.vow(timer_set(CHECK_EVERY)), llam (_) =>
      _check(checks - 1, true, url, url_len, first, first_len, answer))
  else (case+ get_visibility() of
    | Hidden() => $P.finish<visibility>(visibility_next(), llam (_) =>
        _check(checks - 1, true, url, url_len, first, first_len, answer))
    | Visible() => let
        val @(url_frozen, url_borrow) = $A.freeze<byte>(url)
        val reading = _stamp_read(url_borrow, url_len)
        val () = $A.drop<byte>(url_frozen, url_borrow)
        val url = $A.thaw<byte>(url_frozen)
      in $P.finish<stamp>(reading, llam (now) =>
        case+ now of
        | ~Stamp(bytes, k) =>
          if k = first_len then let
            val same = _same(bytes, first, k, 0)
            val () = $A.free<byte>(bytes)
          in
            if same then _check(checks - 1, false, url, url_len, first, first_len, answer)
            else let
              val () = $A.free<byte>(url)
              val () = $A.free<byte>(first)
            in $P.resolve<build_change>(answer, NewBuild()) end
          end
          else let
            val () = $A.free<byte>(bytes)
            val () = $A.free<byte>(url)
            val () = $A.free<byte>(first)
          in $P.resolve<build_change>(answer, NewBuild()) end
        (* a check that failed (no network, say) is tried again *)
        | ~Unstamped() => _check(checks - 1, false, url, url_len, first, first_len, answer))
      end)

implement build_watch{lu}{nu}(url, url_len) = let
  val @(p, answer) = $P.create<build_change>()
  val copy = $A.alloc<byte>(url_len)
  val () = $A.write_borrow(copy, 0, url, url_len)
  val reading = _stamp_read(url, url_len)
  val () = $P.finish<stamp>(reading, llam (first) =>
    case+ first of
    | ~Stamp(bytes, k) =>
      if k > 0 then _check(CHECKS, false, copy, url_len, bytes, k, answer)
      else let
        val () = $A.free<byte>(bytes)
        val () = $A.free<byte>(copy)
      in $P.resolve<build_change>(answer, WatchEnded()) end
    | ~Unstamped() => let
        val () = $A.free<byte>(copy)
      in $P.resolve<build_change>(answer, WatchEnded()) end)
in $P.vow(p) end

end (* #target wasm *)
