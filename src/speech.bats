(* speech -- reading text aloud, and its sentences, for bridge *)

#include "share/atspre_staload.hats"
staload "./event.bats"
staload "./decompress.bats"

#use array as A
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* Whether text can be read aloud here: the Web Speech API
   (speechSynthesis), in a browser, or in the app where its web view
   has it *)
#pub fun speech_available(): bool

(* The voices, as a blob of UTF-8 lines, one a voice: its name, a tab,
   its language (a BCP 47 tag), a tab, 1 when it is the default voice
   (else 0), and a newline (a tab or newline in a name or language is a
   space); none when there are none yet. A browser may load its voices
   late: the speech listener's event 4 says they changed. *)
#pub fun speech_voices(): $R.option([k:nat] dblob(k))

(* Reads text[0, text_len) aloud, after what is queued: in language
   lang[0, lang_len) (the default when lang_len is 0), with the voice
   named voice[0, voice_len) (the default for the language when
   voice_len is 0, or no voice has that name), at rate_hundredths / 100
   of the normal speed. Its number (1 and up, in the speech listener's
   events), or 0 when speech is not available. *)
#pub fun speech_speak
  {lt:agz}{nt:pos}{ll:agz}{nl:pos}{kl:nat | kl <= nl}
  {lv:agz}{nv:pos}{kv:nat | kv <= nv}{rate:int | 25 <= rate; rate <= 400}
  (text: !$A.borrow(byte, lt, nt), text_len: int nt,
   lang: !$A.borrow(byte, ll, nl), lang_len: int kl,
   voice: !$A.borrow(byte, lv, nv), voice_len: int kv,
   rate_hundredths: int rate): [u:nat] int u

(* Pauses what is being read, to go on with speech_resume *)
#pub fun speech_pause(): void

#pub fun speech_resume(): void

(* Stops what is being read, and drops what is queued (each gets an
   error event, code 1) *)
#pub fun speech_cancel(): void

(* The listener for speech's events. Each payload is 9 bytes: the kind
   (0 started, 1 a boundary, 2 ended, 3 an error, 4 the voices changed),
   the utterance's number (int32 LE, as speech_speak gave it; 0 for 4),
   and a value (int32 LE): for a boundary, the UTF-8 byte offset in the
   utterance's text of the word (or sentence) reached; for an error, 1
   interrupted or cancelled, 2 not allowed (no user activation yet), 3
   no such language or voice, 0 any other; else 0. *)
#pub fun listen_speech
  (listener_id: listener_id,
   callback: (event_payload) -<cloref1> int): void

(* The sentences of text[0, text_len) (UTF-8), in language
   lang[0, lang_len) (the default when lang_len is 0), as a blob of each
   one's start, an int32 LE UTF-8 byte offset into the text, in order
   (the first is 0; each runs to the next one's start, the last to the
   end, its trailing spaces with it). Intl.Segmenter where there is one;
   else a sentence ends after a run of . ! ? or an ellipsis, or their
   CJK forms (U+3002, U+FF01, U+FF1F), with the closing quotes and
   brackets after it and the space after those. None when it could not
   be made. *)
#pub fun segment_sentences
  {lt:agz}{nt:pos}{ll:agz}{nl:pos}{kl:nat | kl <= nl}
  (text: !$A.borrow(byte, lt, nt), text_len: int nt,
   lang: !$A.borrow(byte, ll, nl), lang_len: int kl)
  : $R.option([k:nat] dblob(k))

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_listener_set(int id, void *cb);
extern int bats_js_speech_available(void);
extern int bats_js_speech_voices(void);
extern int bats_js_speech_speak(void*, int, void*, int, void*, int, int);
extern void bats_js_speech_control(int);
extern void bats_js_listen_speech(int);
extern int bats_js_segment_sentences(void*, int, void*, int);
%}
extern fun _bats_js_speech_available
  (): int = "mac#bats_js_speech_available"
extern fun _bats_js_speech_voices
  (): [v:int] int v = "mac#bats_js_speech_voices"
extern fun _bats_js_speech_speak
  (text: ptr, text_len: int, lang: ptr, lang_len: int,
   voice: ptr, voice_len: int, rate: int): [v:int] int v = "mac#bats_js_speech_speak"
extern fun _bats_js_speech_control
  (control: int): void = "mac#bats_js_speech_control"
extern fun _bats_js_listen_speech
  (listener_id: int): void = "mac#bats_js_listen_speech"
extern fun _bats_js_segment_sentences
  (text: ptr, text_len: int, lang: ptr, lang_len: int)
  : [v:int] int v = "mac#bats_js_segment_sentences"
end

implement speech_available() = _bats_js_speech_available() > 0

implement speech_voices() = blob_claim(_bats_js_speech_voices())

(* JS's word is checked here, once *)
implement speech_speak{lt}{nt}{ll}{nl}{kl}{lv}{nv}{kv}{rate}
  (text, text_len, lang, lang_len, voice, voice_len, rate_hundredths) = let
  val u = _bats_js_speech_speak(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(text) end, text_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(lang) end, lang_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(voice) end, voice_len,
    rate_hundredths)
in if u > 0 then u else 0 end

implement speech_pause() = _bats_js_speech_control(0)

implement speech_resume() = _bats_js_speech_control(1)

implement speech_cancel() = _bats_js_speech_control(2)

implement listen_speech(listener_id, callback) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val () = $UNSAFE begin $extfcall(void, "bats_listener_set", listener_id, cbp) end
in _bats_js_listen_speech(listener_id) end

implement segment_sentences{lt}{nt}{ll}{nl}{kl}(text, text_len, lang, lang_len) =
  blob_claim(_bats_js_segment_sentences(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(text) end, text_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(lang) end, lang_len))

end (* #target wasm *)
