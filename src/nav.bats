(* nav -- browser navigation: URL, hash, history for bridge *)

#include "share/atspre_staload.hats"

#use array as A
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

#pub fun get_url
  {l:agz}{n:pos}
  (out: !$A.arr(byte, l, n), max_len: int n): $R.result(int, int)

#pub fun get_hash
  {l:agz}{n:pos}
  (out: !$A.arr(byte, l, n), max_len: int n): $R.result(int, int)

#pub fun set_hash
  {lb:agz}{n:nat}
  (hash: !$A.borrow(byte, lb, n), hash_len: int n): void

#pub fun replace_state
  {lb:agz}{n:nat}
  (url: !$A.borrow(byte, lb, n), url_len: int n): void

#pub fun push_state
  {lb:agz}{n:nat}
  (url: !$A.borrow(byte, lb, n), url_len: int n): void

#pub fun reload(): void

#pub fun on_popstate
  (url_len: int): void = "ext#bats_on_popstate"

#pub fun set_popstate_callback
  (cb: (int) -<cloref1> int): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_listener_set(int id, void *cb);
extern void *bats_listener_get(int id);
extern int bats_js_get_url(void*, int);
extern int bats_js_get_url_hash(void*, int);
extern void bats_js_set_url_hash(void*, int);
extern void bats_js_replace_state(void*, int);
extern void bats_js_push_state(void*, int);
extern void bats_js_reload(void);
%}
extern fun _bats_js_get_url
  (out: ptr, max_len: int): int = "mac#bats_js_get_url"
extern fun _bats_js_get_url_hash
  (out: ptr, max_len: int): int = "mac#bats_js_get_url_hash"
extern fun _bats_js_set_url_hash
  (hash: ptr, hash_len: int): void = "mac#bats_js_set_url_hash"
extern fun _bats_js_replace_state
  (url: ptr, url_len: int): void = "mac#bats_js_replace_state"
extern fun _bats_js_push_state
  (url: ptr, url_len: int): void = "mac#bats_js_push_state"
extern fun _bats_js_reload
  (): void = "mac#bats_js_reload"
end

implement get_url{l}{n}(out, max_len) = let
  val r = _bats_js_get_url(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end,
    max_len)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement get_hash{l}{n}(out, max_len) = let
  val r = _bats_js_get_url_hash(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end,
    max_len)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement set_hash{lb}{n}(hash, hash_len) =
  _bats_js_set_url_hash(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(hash) end,
    hash_len)

implement replace_state{lb}{n}(url, url_len) =
  _bats_js_replace_state(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end,
    url_len)

implement push_state{lb}{n}(url, url_len) =
  _bats_js_push_state(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end,
    url_len)

implement reload() = _bats_js_reload()

implement set_popstate_callback(cb) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(cb) end
in $UNSAFE begin $extfcall(void, "bats_listener_set", 999999, cbp) end end

implement on_popstate(url_len) = let
  val cbp = $UNSAFE begin $extfcall(ptr, "bats_listener_get", 999999) end
in
  if ptr_isnot_null(cbp) then let
    val cb = $UNSAFE begin $UNSAFE.cast{(int) -<cloref1> int}(cbp) end
    val _ = cb(url_len)
  in () end
  else ()
end

end (* #target wasm *)
