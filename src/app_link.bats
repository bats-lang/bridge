(* app_link -- the addresses the native app is opened at

   An OAuth sign-in in a native app comes back to the app at its own
   address (RFC 8252: a private-use URI scheme for the redirect), after
   browser_tab.bats opened the sign-in page. App (Capacitor): the App
   plugin passes each address the app is opened at (its appUrlOpen,
   Android's VIEW intents, kept until a listener takes them, so one that
   started the app is passed too; @capacitor/app). The app's manifest
   says which scheme opens it (an intent filter the app writes). A
   browser has no App plugin: there the page comes back to its own
   address (nav.bats). *)

#include "share/atspre_staload.hats"
staload "./event.bats"
staload "./decompress.bats"

#use array as A
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* Whether the app is told the addresses it is opened at: the native
   app with its App plugin; false in a browser *)
#pub fun app_link_available(): bool

(* A listener for the addresses the app is opened at, each passed as its
   UTF-8 bytes (an address JS cannot give, or an empty one, is not
   passed). An address that started the app is passed too, once the
   listener is set. The callback frees the blob. *)
#pub fun listen_app_link
  (listener_id: listener_id,
   callback: ([k:pos] dblob(k)) -<lincloptr1> void): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

$UNSAFE begin
%{
extern void bats_listener_set_decoded(int id, void *decoder, void *inner);
extern int bats_js_app_link_available(void);
extern void bats_js_listen_app_link(int);
%}
extern fun _bats_js_app_link_available
  (): int = "mac#bats_js_app_link_available"
extern fun _bats_js_listen_app_link
  (listener_id: int): void = "mac#bats_js_listen_app_link"
end

implement app_link_available() = _bats_js_app_link_available() > 0

(* The event's address: its blob, when there is one and it is not
   empty *)
fn _link (payload: event_payload): $R.option([k:pos] dblob(k)) =
  case+ event_take(payload) of
  | ~$R.some(blob) =>
    if blob_len(blob) > 0 then $R.some(blob)
    else let val () = blob_free(blob) in $R.none() end
  | ~$R.none() => $R.none()

(* The slot holds the decoder and the callback, and frees both (the
   decoder holds only the callback's pointer). *)
implement listen_app_link(listener_id, callback) = let
  val inner = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val decode = llam (payload: event_payload): int =<lincloptr1>
    case+ _link(payload) of
    | ~$R.some(blob) => let
        val call = $UNSAFE begin $UNSAFE.cast{([k:pos] dblob(k)) -<cloref1> void}(inner) end
        val () = call(blob)
      in 0 end
    | ~$R.none() => 0
  val decoder = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(decode) end
  val () = $UNSAFE begin
    $extfcall(void, "bats_listener_set_decoded", listener_id, decoder, inner) end
in _bats_js_listen_app_link(listener_id) end

end (* #target wasm *)
