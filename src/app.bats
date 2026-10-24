(* app -- where the app runs, and installing it, for bridge *)

#include "share/atspre_staload.hats"
staload "./event.bats"
staload "./decompress.bats"

#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* How the offer to install ended. JS's answer is decoded here, once: a
   code it should not send is InstallUnavailable. *)
#pub datatype install_outcome =
  | InstallAccepted     (* the user installed the app *)
  | InstallDismissed    (* the user said no *)
  | InstallUnavailable  (* there was no offer, or showing it failed *)

(* How the offer to install ended, each outcome its own. JS's answer is
   decoded here, once: the user's accepted and dismissed, no offer, the
   offer rejected or thrown (what, as text, none when JS could not write
   it down), reading the answer thrown (as text), an answer that is
   neither accepted nor dismissed (as text), and a code JS never gives.
   Linear (the text), so the one consumer takes it apart with case+ ~; one
   no consumer takes is freed by promise's dispose. *)
#pub datavtype install_answer =
  | InstallAnswerAccepted                                    (* the user installed the app *)
  | InstallAnswerDismissed                                   (* the user said no *)
  | InstallAnswerNoOffer                                     (* there was no offer *)
  | InstallAnswerRejected of $R.option([n:nat] dblob(n))     (* the offer was rejected or threw: what, as text *)
  | InstallAnswerThrown of $R.option([n:nat] dblob(n))       (* reading the user's choice threw: what, as text *)
  | InstallAnswerOdd of $R.option([n:nat] dblob(n))          (* the choice is neither accepted nor dismissed: as text *)
  | InstallAnswerUnexpected of Int                           (* a code JS never gives *)

(* The offer's coming and going, as listen_install_prompt passes it *)
#pub datatype install_offer =
  | InstallOffered    (* there is an offer now *)
  | InstallWithdrawn  (* it was used, or the app was installed *)

(* Whether the page runs in the native app (Capacitor's
   isNativePlatform()), not in a browser *)
#pub fun is_native_platform(): bool

(* Whether the page is in iOS Safari's browser, not added to the Home
   Screen (navigator.standalone is false), where installing is the
   user's own Share, Add to Home Screen; false elsewhere *)
#pub fun is_ios_browser(): bool

(* Whether the browser offers to install the app now: it fired
   beforeinstallprompt, which bridge keeps from the page's start (the
   browser's own banner is held back). Browser only: an installed app,
   or the native app, has no offer. *)
#pub fun install_prompt_available(): bool

(* Shows the browser's offer to install the app; call it from a click's
   listener. The offer is used up. The promise resolves with how it
   ended. Deprecated (app, bridge#229): it folds a rejection, a thrown
   answer and an odd answer into InstallUnavailable;
   install_prompt_answer tells them apart. *)
#pub fun install_prompt(): $P.promise(install_outcome, $P.Chained)

(* install_prompt with every outcome its own *)
#pub fun install_prompt_answer(): $P.promise(install_answer, $P.Chained)

(* A listener for the offer's coming and going (browser only), passed
   whether there is an offer now (install_prompt_available, read as the
   event comes). An offer made before the listener is set is not passed
   to it: ask install_prompt_available. *)
#pub fun listen_install_prompt
  (listener_id: listener_id,
   callback: (install_offer) -<lincloptr1> void): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_listener_set_decoded(int id, void *decoder, void *inner);
extern int bats_js_is_native_platform(void);
extern int bats_js_is_ios_browser(void);
extern int bats_js_install_prompt_available(void);
extern void bats_js_install_prompt(int);
extern int bats_js_install_text(int);
extern void bats_js_listen_install_prompt(int);
%}
extern fun _bats_js_is_native_platform
  (): int = "mac#bats_js_is_native_platform"
extern fun _bats_js_is_ios_browser
  (): int = "mac#bats_js_is_ios_browser"
extern fun _bats_js_install_prompt_available
  (): int = "mac#bats_js_install_prompt_available"
extern fun _bats_js_install_prompt
  (resolver_id: int): void = "mac#bats_js_install_prompt"
extern fun _bats_js_install_text
  (resolver_id: int): int = "mac#bats_js_install_text"
extern fun _bats_js_listen_install_prompt
  (listener_id: int): void = "mac#bats_js_listen_install_prompt"
end

implement is_native_platform() = _bats_js_is_native_platform() > 0

implement is_ios_browser() = _bats_js_is_ios_browser() > 0

implement install_prompt_available() = _bats_js_install_prompt_available() > 0

(* What the offer rejected with, threw or answered, as text: JS kept it
   under the call's number, and none when it could not be written down *)
fn _install_text (resolver_id: int): $R.option([n:nat] dblob(n)) = let
  val handle = _bats_js_install_text(resolver_id)
in
  if handle <= 0 then $R.none()
  else blob_claim($UNSAFE begin $UNSAFE.cast{blob_handle}(handle) end)
end

(* JS's codes: 1 accepted, 0 dismissed, 2 no offer, -3 rejected or threw,
   -4 reading the choice threw, -5 neither accepted nor dismissed (the
   text of -3 to -5 kept by the call's number); any other is a code JS
   never gives *)
fn _install_answer (code: Int, resolver_id: int): install_answer =
  if code = 1 then InstallAnswerAccepted()
  else if code = 0 then InstallAnswerDismissed()
  else if code = 2 then InstallAnswerNoOffer()
  else if code = ~3 then InstallAnswerRejected(_install_text(resolver_id))
  else if code = ~4 then InstallAnswerThrown(_install_text(resolver_id))
  else if code = ~5 then InstallAnswerOdd(_install_text(resolver_id))
  else InstallAnswerUnexpected(code)

fn _free_install_text (text: $R.option([n:nat] dblob(n))): void =
  case+ text of ~$R.some(blob) => blob_free(blob) | ~$R.none() => ()

(* An answer nobody took: its text freed *)
implement $P.dispose<install_answer>(answer) =
  case+ answer of
  | ~InstallAnswerAccepted() => ()
  | ~InstallAnswerDismissed() => ()
  | ~InstallAnswerNoOffer() => ()
  | ~InstallAnswerRejected(text) => _free_install_text(text)
  | ~InstallAnswerThrown(text) => _free_install_text(text)
  | ~InstallAnswerOdd(text) => _free_install_text(text)
  | ~InstallAnswerUnexpected(_) => ()

(* An outcome nobody took: nothing to free *)
implement $P.dispose<install_outcome>(_) = ()

implement install_prompt_answer() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_install_prompt(id)
in $P.and_then<Int><install_answer>(p, llam (code) =>
  $P.ret<install_answer>(_install_answer(code, id))) end

(* The old outcome, as it always was (install): accepted; dismissed, and also
   an outcome that is neither (the old JS wrote 0 for anything but accepted);
   InstallUnavailable for no offer and for a rejection or a throw (the text freed) *)
fn _install_outcome (answer: install_answer): install_outcome =
  case+ answer of
  | ~InstallAnswerAccepted() => InstallAccepted()
  | ~InstallAnswerDismissed() => InstallDismissed()
  | ~InstallAnswerNoOffer() => InstallUnavailable()
  | ~InstallAnswerRejected(text) => let val () = _free_install_text(text) in InstallUnavailable() end
  | ~InstallAnswerThrown(text) => let val () = _free_install_text(text) in InstallUnavailable() end
  | ~InstallAnswerOdd(text) => let val () = _free_install_text(text) in InstallDismissed() end
  | ~InstallAnswerUnexpected(_) => InstallUnavailable()

implement install_prompt() =
  $P.and_then<install_answer><install_outcome>(install_prompt_answer(), llam (answer) =>
    $P.ret<install_outcome>(_install_outcome(answer)))

(* The event carries no payload: whether there is an offer is read as it
   comes, so there is nothing to decode that could be wrong. The slot
   holds the decoder and the callback, and frees both (the decoder
   holds only the callback's pointer). *)
implement listen_install_prompt(listener_id, callback) = let
  val inner = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val decode = llam (payload: event_payload): int =<lincloptr1> let
    val call = $UNSAFE begin $UNSAFE.cast{(install_offer) -<cloref1> void}(inner) end
    val () = call(if install_prompt_available()
      then InstallOffered() else InstallWithdrawn())
  in 0 end
  val decoder = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(decode) end
  val () = $UNSAFE begin
    $extfcall(void, "bats_listener_set_decoded", listener_id, decoder, inner) end
in _bats_js_listen_install_prompt(listener_id) end

end (* #target wasm *)
