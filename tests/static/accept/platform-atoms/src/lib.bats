#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload SC = "wasm.bats-packages.dev/bridge/src/screen.sats"
staload SH = "wasm.bats-packages.dev/bridge/src/share.sats"
staload SP = "wasm.bats-packages.dev/bridge/src/speech.sats"
staload ST = "wasm.bats-packages.dev/bridge/src/storage.sats"
staload AP = "wasm.bats-packages.dev/bridge/src/app.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

(* Each atom is called only where it is available: full screen, half
   brightness, the text read at one and a half times its speed in the
   default language and voice (lang and voice of length 0), its
   sentences, the text shared with no title, and storage kept *)
fn f (): int = let
  val () = (if $SC.fullscreen_available() then $SC.fullscreen_enter() else ())
  val () = (if $SC.brightness_available() then $SC.brightness_set(50) else ())
  val text = $A.alloc<byte>(5)
  val () = $A.write_text(text, 0, $A.text_lit("Hi. O"), 5)
  val @(frozen, borrowed) = $A.freeze<byte>(text)
  val lang = $A.dup<byte>(frozen, borrowed)
  val voice = $A.dup<byte>(frozen, borrowed)
  val utterance = (if $SP.speech_available()
    then $SP.speech_speak(borrowed, 5, lang, 0, voice, 0, 150) else 0): int
  val starts = (case+ $SP.segment_sentences(borrowed, 5, lang, 0) of
    | ~$R.none() => 0
    | ~$R.some(b) => let val n = $BD.blob_len(b) val () = $BD.blob_free(b) in n / 4 end): int
  val () = (if $SH.share_available()
    then $P.discard<Int>($SH.share_text(lang, 0, borrowed, 5)) else ())
  val () = $A.drop<byte>(frozen, voice)
  val () = $A.drop<byte>(frozen, lang)
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
  val () = (if $AP.is_native_platform() then () else $P.discard<Int>($ST.storage_persist()))
  val offset = $TM.timezone_offset_minutes()
in utterance + starts + offset end
