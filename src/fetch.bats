(* fetch -- network fetch with promise-based async for bridge *)

#include "share/atspre_staload.hats"

#use array as A
#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

#pub fun fetch
  {lb:agz}{n:pos}
  (url: !$A.borrow(byte, lb, n), url_len: int n)
  : $P.promise(int, $P.Pending)

#pub fun get_body_len(): int

#pub fun get_body
  {n:pos | n <= 1048576}
  (len: int n): [l:agz] $A.arr(byte, l, n)

#pub fun on_fetch_complete
  (resolver_id: int, status: int, body_len: int)
  : void = "ext#bats_on_fetch_complete"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

extern fun _bats_js_fetch
  (url: ptr, url_len: int, resolver_id: int): void = "mac#bats_js_fetch"

implement fetch{lb}{n}(url, url_len) = let
  val @(p, r) = $P.create<int>()
  val id = $P.stash(r)
  val () = _bats_js_fetch(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end, url_len,
    id)
in p end

implement get_body_len() =
  stash_get_int(0)

implement get_body{n}(len) =
  stash_read(stash_get_int(1), len)

implement on_fetch_complete(resolver_id, status, body_len) = let
  val () = stash_set_int(0, body_len)
in $P.fire(resolver_id, status) end

end (* #target wasm *)
