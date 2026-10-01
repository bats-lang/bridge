#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload SC = "wasm.bats-packages.dev/bridge/src/screen.sats"
staload SH = "wasm.bats-packages.dev/bridge/src/share.sats"
staload SP = "wasm.bats-packages.dev/bridge/src/speech.sats"
staload ST = "wasm.bats-packages.dev/bridge/src/storage.sats"
staload AP = "wasm.bats-packages.dev/bridge/src/app.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

(* The sentences counted, each start in the text *)
fun count {n,f:int | f <= n} .<n - f>. (s: $SP.sentences(n, f)): int =
  case+ s of
  | ~$SP.SentencesEnd() => 0
  | ~$SP.Sentence(_, rest) => 1 + count(rest)

(* The voices counted, the default ones twice *)
fun weigh {k:nat} .<k>. (v: $SP.voices(k)): int =
  case+ v of
  | ~$SP.VoicesEnd() => 0
  | ~$SP.VoicesMore(one, rest) => let
      val+ ~$SP.Voice(name, _, lang, is_default) = one
      val () = $A.free<byte>(name)
      val () = (case+ lang of
        | ~$SP.NoLanguage() => ()
        | ~$SP.Language(tag, _) => $A.free<byte>(tag))
    in ((if is_default then 2 else 1): int) + weigh(rest) end

(* Each atom is called only where it is available, and each answer is
   matched in full: full screen, half brightness and then the system's,
   the text read at one and a half times its speed in the default
   language and voice (lang and voice of length 0), its sentences, the
   voices, the text shared with no title, the rotation locked, storage
   kept and the app offered for installing *)
fn f (): int = let
  val () = (if $SC.fullscreen_available() then $SC.fullscreen_enter() else ())
  val () = $SC.listen_fullscreen(1, lam (change) =>
    case+ change of
    | $SC.FullscreenEntered() => ()
    | $SC.FullscreenLeft() => ())
  val () = (if $SC.brightness_available() then let
      val () = $SC.brightness_set($SC.Level(50))
    in $SC.brightness_set($SC.FollowSystem()) end else ())
  val () = $P.finish<$SC.brightness_reading>($SC.brightness_get(), lam (reading) =>
    case+ reading of
    | $SC.Brightness(level) => let val _ = level + 0 in () end
    | $SC.SystemBrightness() => ()
    | $SC.BrightnessUnreadable() => ())
  val () = (if $SC.orientation_available() then
    $P.finish<$SC.lock_outcome>($SC.orientation_lock_current(), lam (lock) =>
      case+ lock of
      | $SC.Locked() => ()
      | $SC.LockRefused() => ()) else ())
  val text = $A.alloc<byte>(5)
  val () = $A.write_text(text, 0, $A.text_lit("Hi. O"), 5)
  val @(frozen, borrowed) = $A.freeze<byte>(text)
  val lang = $A.dup<byte>(frozen, borrowed)
  val voice = $A.dup<byte>(frozen, borrowed)
  val utterance = (if $SP.speech_available() then
    (case+ $SP.speech_speak(borrowed, 5, lang, 0, voice, 0, 150) of
     | ~$SP.Speaking(u) => u
     | ~$SP.SpeechUnavailable() => 0)
    else 0): int
  val starts = (case+ $SP.segment_sentences(borrowed, 5, lang, 0) of
    | ~$R.none() => 0
    | ~$R.some(s) => count(s)): int
  val voices = (case+ $SP.speech_voices() of
    | ~$R.none() => 0
    | ~$R.some(v) => weigh(v)): int
  val () = (if $SH.share_available() then
    $P.finish<$SH.share_outcome>($SH.share_text(lang, 0, borrowed, 5), lam (outcome) =>
      case+ outcome of
      | $SH.Shared() => ()
      | $SH.Cancelled() => ()
      | $SH.ShareFailed() => ()) else ())
  val () = (if $SH.share_file_available() then
    $P.finish<$SH.file_share_outcome>($SH.share_file(borrowed, 5, voice, 5, lang, 5), lam (outcome) =>
      case+ outcome of
      | $SH.FileShared() => ()
      | $SH.FileShareCancelled() => ()
      | $SH.FileShareFailed() => ()
      | $SH.FilesNotShareable() => ()) else ())
  val () = $A.drop<byte>(frozen, voice)
  val () = $A.drop<byte>(frozen, lang)
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
  val () = (if $AP.is_native_platform() then () else
    $P.finish<$ST.persist_outcome>($ST.storage_persist(), lam (kept) =>
      case+ kept of
      | $ST.Persisted() => ()
      | $ST.NotPersisted() => ()))
  val () = $AP.listen_install_prompt(2, lam (offer) =>
    case+ offer of
    | $AP.InstallOffered() => ()
    | $AP.InstallWithdrawn() => ())
  val () = (if $AP.install_prompt_available() then
    $P.finish<$AP.install_outcome>($AP.install_prompt(), lam (outcome) =>
      case+ outcome of
      | $AP.InstallAccepted() => ()
      | $AP.InstallDismissed() => ()
      | $AP.InstallUnavailable() => ()) else ())
  val offset = $TM.timezone_offset_minutes()
in utterance + starts + voices + offset end
