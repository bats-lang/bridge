(* nav -- browser navigation: URL, hash, history for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* The page's URL in out: its length, at most max_len (a longer one is
   cut) *)
#pub fun get_url
  {l:agz}{n:pos}
  (out: !$A.arr(byte, l, n), max_len: int n): [v:nat | v <= n] int v

(* The URL's hash ("#..." or empty) in out, as get_url *)
#pub fun get_hash
  {l:agz}{n:pos}
  (out: !$A.arr(byte, l, n), max_len: int n): [v:nat | v <= n] int v

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

(* Goes one entry back in the session's history (history.back()): as
   the browser's Back button does, so the page gets a popstate when the
   entry it goes to is its own; at the first entry nothing happens. An
   app that pushed an entry (push_state) and no longer needs it takes it
   back with this *)
#pub fun history_back(): void

(* Leaves the page for the https address url[0, url_len) (a sign-in
   page, say an OAuth authorization, which comes back to the page's own
   address): whether it is left. An address that is not https:// is
   refused here, and nothing is done *)
#pub fun navigate_away
  {lb:agz}{n:nat}
  (url: !$A.borrow(byte, lb, n), url_len: int n): bool

(* Whether url[0, url_len) is an https address (starts with https://):
   the one check of the atoms that hand an address off the page
   (navigate_away, browser_tab.bats' browser_tab_open) *)
#pub fun is_https
  {lb:agz}{n:nat}
  (url: !$A.borrow(byte, lb, n), url_len: int n): bool

#pub fun on_popstate
  (url: Int): void = "ext#bats_on_popstate"

(* The callback gets the new URL, as a blob (none when JS could not
   read it), and frees it. It is a linear closure (llam): the one set
   before it is freed. *)
#pub fun set_popstate_callback
  (cb: ($R.option([k:nat] dblob(k))) -<lincloptr1> int): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

(* JS's code for a blob, as a handle: bridge's own atoms are the only
   ones that give one *)
fn _claimed_blob (code: int): $R.option([n:nat] dblob(n)) =
  blob_claim($UNSAFE begin $UNSAFE.cast{blob_handle}(code) end)

$UNSAFE begin
%{
extern void bats_popstate_set(void *cb);
extern void *bats_popstate_get(void);
extern void bats_listener_enter(void);
extern void bats_listener_leave(void);
extern int bats_js_get_url(void*, int);
extern int bats_js_get_url_hash(void*, int);
extern void bats_js_set_url_hash(void*, int);
extern void bats_js_replace_state(void*, int);
extern void bats_js_push_state(void*, int);
extern void bats_js_reload(void);
extern void bats_js_history_back(void);
extern int bats_js_navigate_away(void*, int);
%}
extern fun _bats_js_get_url
  (out: ptr, max_len: int): [v:int] int v = "mac#bats_js_get_url"
extern fun _bats_js_get_url_hash
  (out: ptr, max_len: int): [v:int] int v = "mac#bats_js_get_url_hash"
extern fun _bats_js_set_url_hash
  (hash: ptr, hash_len: int): void = "mac#bats_js_set_url_hash"
extern fun _bats_js_replace_state
  (url: ptr, url_len: int): void = "mac#bats_js_replace_state"
extern fun _bats_js_push_state
  (url: ptr, url_len: int): void = "mac#bats_js_push_state"
extern fun _bats_js_reload
  (): void = "mac#bats_js_reload"
extern fun _bats_js_history_back
  (): void = "mac#bats_js_history_back"
extern fun _bats_js_navigate_away
  (url: ptr, url_len: int): int = "mac#bats_js_navigate_away"
end

implement is_https{lb}{n}(url, url_len) = let
  fun starts {i:nat | i <= 8} .<8 - i>. (url: !$A.borrow(byte, lb, n), i: int i): bool =
    if i >= 8 then true
    else if i >= url_len then false
    else if byte2int0($A.read<byte>(url, i)) <> char2int0(string_get_at("https://", i)) then false
    else starts(url, i + 1)
in starts(url, 0) end

(* A length JS wrote, bounded here once: JS writes at most max_len
   bytes, and 0 when it cannot read the URL *)
fn _written {n:pos}{r:int} (r: int r, max_len: int n): [v:nat | v <= n] int v =
  if r < 0 then 0 else if r > max_len then max_len else r

implement get_url{l}{n}(out, max_len) =
  _written(_bats_js_get_url(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end,
    max_len), max_len)

implement get_hash{l}{n}(out, max_len) =
  _written(_bats_js_get_url_hash(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end,
    max_len), max_len)

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

implement history_back() = _bats_js_history_back()

implement navigate_away{lb}{n}(url, url_len) =
  if ~is_https(url, url_len) then false
  else _bats_js_navigate_away($UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end, url_len) > 0

implement set_popstate_callback(cb) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(cb) end
in $UNSAFE begin $extfcall(void, "bats_popstate_set", cbp) end end

implement on_popstate(url) = let
  val cbp = $UNSAFE begin $extfcall(ptr, "bats_popstate_get") end
in
  if ptr_isnot_null(cbp) then let
    val () = $UNSAFE begin $extfcall(void, "bats_listener_enter") end
    val cb = $UNSAFE begin $UNSAFE.cast{($R.option([k:nat] dblob(k))) -<cloref1> int}(cbp) end
    val _ = cb(_claimed_blob(url))
  in $UNSAFE begin $extfcall(void, "bats_listener_leave") end end
  else ()
end

end (* #target wasm *)
