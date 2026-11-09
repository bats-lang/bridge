(* image_error -- an image that failed to draw (bridge#277, for quire#1061)

   An <img> whose source the engine cannot draw (a corrupt or an
   undecodable file, such as a JPEG XL in an engine without the decoder)
   fires an error event on the image. That event does not bubble, so
   listen_document (event.bats) never hears it: bridge listens once in the
   capture phase on the document, and passes the failed image's node id to
   the app, which decides what to do (the manifest's fallback, for quire).
   An image that draws is not passed. An image with no id, which is not the
   app's, is not passed either. *)

#include "share/atspre_staload.hats"
staload "./event.bats"
staload "./decompress.bats"

#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* What the app is told. Linear (the id's bytes), so the consumer takes it
   apart with case+ ~ and frees the blob *)
#pub datavtype image_error =
  | ImageFailed of ([k:pos] dblob(k))  (* the failed <img>'s node id, as UTF-8 bytes *)

(* Whether failed images are reported: false where the page has no document
   to listen on *)
#pub fun image_error_available(): bool

(* A listener for the images that fail to draw, called once for each
   failure, with the image's node id. One listener at a time: a later call
   replaces the earlier one's callback in the slot. *)
#pub fun listen_image_error
  (listener_id: listener_id,
   callback: (image_error) -<lincloptr1> void): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

$UNSAFE begin
%{
extern void bats_listener_set_decoded(int id, void *decoder, void *inner);
extern int bats_js_image_error_available(void);
extern void bats_js_listen_image_error(int);
%}
extern fun _bats_js_image_error_available
  (): int = "mac#bats_js_image_error_available"
extern fun _bats_js_listen_image_error
  (listener_id: int): void = "mac#bats_js_listen_image_error"
end

implement image_error_available() = _bats_js_image_error_available() > 0

(* The event's node id: its blob, when there is one and it is not empty
   (JS passes none otherwise) *)
fn _failed (payload: event_payload): $R.option(image_error) =
  case+ event_take(payload) of
  | ~$R.some(blob) =>
    if blob_len(blob) > 0 then $R.some(ImageFailed(blob))
    else let val () = blob_free(blob) in $R.none() end
  | ~$R.none() => $R.none()

(* The slot holds the decoder and the callback, and frees both (the
   decoder holds only the callback's pointer). *)
implement listen_image_error(listener_id, callback) = let
  val inner = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val decode = llam (payload: event_payload): int =<lincloptr1>
    case+ _failed(payload) of
    | ~$R.some(failed) => let
        val call = $UNSAFE begin $UNSAFE.cast{(image_error) -<cloref1> void}(inner) end
        val () = call(failed)
      in 0 end
    | ~$R.none() => 0
  val decoder = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(decode) end
  val () = $UNSAFE begin
    $extfcall(void, "bats_listener_set_decoded", listener_id, decoder, inner) end
in _bats_js_listen_image_error(listener_id) end

end (* #target wasm *)
