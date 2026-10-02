(* notify -- notifications and push subscriptions for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* The answer to asking for notifications. JS's answer is decoded here,
   once: anything it sends that is not one of its codes is Denied. *)
#pub datatype permission =
  | Granted
  | Denied     (* refused, or notifications are not available here *)
  | NotAsked   (* the question was dismissed, so it can be asked again *)

#pub fun notify_request_permission
  : () -> $P.promise(permission, $P.Chained)

#pub fun notify_show
  {lb:agz}{n:pos}
  (title: !$A.borrow(byte, lb, n), title_len: int n): void

(* A push subscription. None and failed are told apart: NotSubscribed
   is there being none (get_subscription only; subscribing never answers
   it); SubscribeFailed is subscribing, or reading the subscription,
   failing (no service worker, permission refused). Linear: Subscribed
   holds the subscription's JSON as a blob JS keeps until it is freed;
   one no consumer takes is freed by promise's dispose. *)
#pub datavtype subscription =
  | Subscribed of ([n:pos] dblob(n))
  | NotSubscribed
  | SubscribeFailed

(* Subscribes to push with the server's VAPID key *)
#pub fun notify_push_subscribe
  : {lb:agz}{n:pos}
  (!$A.borrow(byte, lb, n), int n) -> $P.promise(subscription, $P.Chained)

(* The current push subscription *)
#pub fun notify_push_get_subscription
  : () -> $P.promise(subscription, $P.Chained)

#pub fun on_permission_result
  (resolver_id: int, granted: Int): void = "ext#bats_on_permission_result"

#pub fun on_push_subscribe
  (resolver_id: int, handle: Int): void = "ext#bats_on_push_subscribe"

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

(* JS's codes: 1 granted, 2 not asked (dismissed), 0 denied *)
fn _permission (code: Int): permission =
  if code = 1 then Granted()
  else if code = 2 then NotAsked()
  else Denied()

(* An answer nobody took: nothing to free. Before
   notify_request_permission, its first use. *)
implement $P.dispose<permission>(_) = ()

implement notify_request_permission() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_notification_request_permission(id)
in $P.and_then<Int><permission>(p, llam (code) =>
  $P.ret<permission>(_permission(code))) end

implement notify_show{lb}{n}(title, title_len) =
  _bats_js_notification_show(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(title) end,
    title_len)

(* JS's codes: a blob's handle (positive), 0 none, anything else (its
   -1) failed. A handle JS did not hand out, or an empty blob, is a
   failure too *)
fn _subscription (code: Int): subscription =
  if code = 0 then NotSubscribed()
  else if code < 0 then SubscribeFailed()
  else (case+ _claimed_blob(code) of
    | ~$R.some(blob) =>
      if blob_len(blob) > 0 then Subscribed(blob)
      else let val () = blob_free(blob) in SubscribeFailed() end
    | ~$R.none() => SubscribeFailed())

(* A subscription nobody took: its blob is freed. Before its first use. *)
implement $P.dispose<subscription>(found) =
  case+ found of
  | ~Subscribed(blob) => blob_free(blob)
  | ~NotSubscribed() => ()
  | ~SubscribeFailed() => ()

fn _subscription_promise (p: $P.promise(Int, $P.Pending)): $P.promise(subscription, $P.Chained) =
  $P.and_then<Int><subscription>(p, llam (code) => $P.ret<subscription>(_subscription(code)))

implement notify_push_subscribe{lb}{n}(vapid, vapid_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_push_subscribe(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(vapid) end,
    vapid_len, id)
in _subscription_promise(p) end

implement notify_push_get_subscription() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_push_get_subscription(id)
in _subscription_promise(p) end

implement on_permission_result(resolver_id, granted) =
  $P.fire(resolver_id, granted)

implement on_push_subscribe(resolver_id, handle) =
  $P.fire(resolver_id, handle)

end (* #target wasm *)
