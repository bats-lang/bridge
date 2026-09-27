(* notify -- notifications and push subscriptions for bridge *)

#include "share/atspre_staload.hats"

#use array as A
#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

#pub fun notify_request_permission
  : () -> $P.promise_pending(Int)

#pub fun notify_show
  {lb:agz}{n:pos}
  (title: !$A.borrow(byte, lb, n), title_len: int n): void

(* Subscribes to push: the promise resolves with a handle to the
   subscription's JSON, to claim with blob_claim (decompress.bats), 0
   when subscribing failed *)
#pub fun notify_push_subscribe
  : {lb:agz}{n:pos}
  (!$A.borrow(byte, lb, n), int n) -> $P.promise_pending(Int)

(* The current push subscription, resolved as notify_push_subscribe's *)
#pub fun notify_push_get_subscription
  : () -> $P.promise_pending(Int)

#pub fun on_permission_result
  (resolver_id: int, granted: Int): void = "ext#bats_on_permission_result"

#pub fun on_push_subscribe
  (resolver_id: int, handle: Int): void = "ext#bats_on_push_subscribe"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_js_notification_request_permission(int);
extern void bats_js_notification_show(void*, int);
extern void bats_js_push_subscribe(void*, int, int);
extern void bats_js_push_get_subscription(int);
%}
extern fun _bats_js_notification_request_permission
  (resolver_id: int): void = "mac#bats_js_notification_request_permission"
extern fun _bats_js_notification_show
  (title: ptr, title_len: int): void = "mac#bats_js_notification_show"
extern fun _bats_js_push_subscribe
  (vapid: ptr, vapid_len: int, resolver_id: int)
  : void = "mac#bats_js_push_subscribe"
extern fun _bats_js_push_get_subscription
  (resolver_id: int): void = "mac#bats_js_push_get_subscription"
end

implement notify_request_permission() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_notification_request_permission(id)
in p end

implement notify_show{lb}{n}(title, title_len) =
  _bats_js_notification_show(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(title) end,
    title_len)

implement notify_push_subscribe{lb}{n}(vapid, vapid_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_push_subscribe(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(vapid) end,
    vapid_len, id)
in p end

implement notify_push_get_subscription() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_push_get_subscription(id)
in p end

implement on_permission_result(resolver_id, granted) =
  $P.fire(resolver_id, granted)

implement on_push_subscribe(resolver_id, handle) =
  $P.fire(resolver_id, handle)

end (* #target wasm *)
