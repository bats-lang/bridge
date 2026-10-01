#include "share/atspre_staload.hats"
#use wasm.bats-packages.dev/bridge as B
staload SP = "wasm.bats-packages.dev/bridge/src/speech.sats"

(* Every speech event is matched, and each failure's reason *)
fn f (): void = $SP.listen_speech(3, lam (event) =>
  case+ event of
  | ~$SP.SpeechStarted(utterance) => let val _ = utterance + 0 in () end
  | ~$SP.SpeechBoundary(utterance, offset) => let val _ = utterance + offset in () end
  | ~$SP.SpeechEnded(_) => ()
  | ~$SP.SpeechFailed(_, failure) => (case+ failure of
    | $SP.Interrupted() => ()
    | $SP.NotAllowed() => ()
    | $SP.NoSuchVoice() => ()
    | $SP.OtherFailure() => ())
  | ~$SP.VoicesChanged() => ())
