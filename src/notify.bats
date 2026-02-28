(* notify -- notifications and push subscriptions for bridge *)

#include "share/atspre_staload.hats"

#use array as A
#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

#pub fun notify_request_permission
  (): $P.promise(int, $P.Pending)

#pub fun notify_show
  {lb:agz}{n:pos}
  (title: !$A.borrow(byte, lb, n), title_len: int n): void

#pub fun notify_push_subscribe
  {lb:agz}{n:pos}
  (vapid: !$A.borrow(byte, lb, n), vapid_len: int n)
  : $P.promise(int, $P.Pending)

#pub fun notify_push_get_result
  {n:pos | n <= 1048576}
  (len: int n): [l:agz] $A.arr(byte, l, n)

#pub fun notify_push_get_subscription
  (): $P.promise(int, $P.Pending)

#pub fun on_permission_result
  (resolver_id: int, granted: int): void = "ext#bats_on_permission_result"

#pub fun on_push_subscribe
  (resolver_id: int, json_len: int): void = "ext#bats_on_push_subscribe"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

extern fun _bats_js_notification_request_permission
  (resolver_id: int): void = "mac#bats_js_notification_request_permission"
extern fun _bats_js_notification_show
  (title: ptr, title_len: int): void = "mac#bats_js_notification_show"
extern fun _bats_js_push_subscribe
  (vapid: ptr, vapid_len: int, resolver_id: int)
  : void = "mac#bats_js_push_subscribe"
extern fun _bats_js_push_get_subscription
  (resolver_id: int): void = "mac#bats_js_push_get_subscription"

implement notify_request_permission() = let
  val @(p, r) = $P.create<int>()
  val id = $P.stash(r)
  val () = _bats_js_notification_request_permission(id)
in p end

implement notify_show{lb}{n}(title, title_len) =
  _bats_js_notification_show(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(title) end,
    title_len)

implement notify_push_subscribe{lb}{n}(vapid, vapid_len) = let
  val @(p, r) = $P.create<int>()
  val id = $P.stash(r)
  val () = _bats_js_push_subscribe(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(vapid) end,
    vapid_len, id)
in p end

implement notify_push_get_result{n}(len) =
  stash_read(stash_get_int(1), len)

implement notify_push_get_subscription() = let
  val @(p, r) = $P.create<int>()
  val id = $P.stash(r)
  val () = _bats_js_push_get_subscription(id)
in p end

implement on_permission_result(resolver_id, granted) =
  $P.fire(resolver_id, granted)

implement on_push_subscribe(resolver_id, json_len) =
  $P.fire(resolver_id, json_len)

end (* #target wasm *)
