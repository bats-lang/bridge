(* speech -- reading text aloud, and its sentences, for bridge *)

#include "share/atspre_staload.hats"
staload "./event.bats"
staload "./decompress.bats"

#use array as A
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* An utterance's number, from 1, as speech_speak gives it and the
   speech listener's events name it *)
#pub typedef utterance = [u:pos] int u

(* A UTF-8 byte offset into an utterance's text *)
#pub typedef speech_offset = [o:nat] int o

(* Why an utterance was not read to its end *)
#pub datatype speech_failure =
  | Interrupted   (* cancelled (speech_cancel), or interrupted *)
  | NotAllowed    (* the page has no user activation yet *)
  | NoSuchVoice   (* no voice for its language or voice *)
  | OtherFailure  (* any other failure, or one bridge does not know *)

(* An event of speech, as listen_speech passes it. Linear, as one is
   made for each word read and there is no garbage collector: the
   callback takes it apart with ~. *)
#pub datavtype speech_event =
  | SpeechStarted of utterance
  (* the word (or sentence) reached, at that offset in the text *)
  | SpeechBoundary of (utterance, speech_offset)
  | SpeechEnded of utterance
  | SpeechFailed of (utterance, speech_failure)
  (* the voices changed (a browser may load them late): ask
     speech_voices again *)
  | VoicesChanged

(* What speech_speak did: the utterance queued, with its number, or
   nothing, as speech is not available here *)
#pub datavtype speech_start =
  | Speaking of utterance
  | SpeechUnavailable

(* A voice's language: a BCP 47 tag, or none given *)
#pub datavtype voice_lang =
  | NoLanguage
  | {l:agz}{n:pos} Language of ($A.arr(byte, l, n), int n)

(* A voice: its name (UTF-8), its language, and whether it is the
   default voice *)
#pub datavtype voice =
  | {l:agz}{n:pos} Voice of ($A.arr(byte, l, n), int n, voice_lang, bool)

(* The voices, k of them *)
#pub datavtype voices(int) =
  | VoicesEnd(0)
  | {k:nat} VoicesMore(k + 1) of (voice, voices(k))

#pub fun voices_free {k:nat} (v: voices(k)): void

(* The sentences of a text of n bytes, from the one at first: each
   starts at s, a UTF-8 byte offset, and runs to the next one's start t
   (the last to n), so each is in the text, none is empty, and they are
   in order. An end is at n. *)
#pub datavtype sentences(int, int) =
  | {n:int} SentencesEnd(n, n)
  | {n,s,t:int | 0 <= s; s < t; t <= n}
    Sentence(n, s) of (int s, sentences(n, t))

#pub fun sentences_free {n,first:int | first <= n} (s: sentences(n, first)): void

(* Whether text can be read aloud here: the Web Speech API
   (speechSynthesis), in a browser, or in the app where its web view
   has it *)
#pub fun speech_available(): bool

(* The voices, in the platform's order: an end when there are none yet
   (a browser may load its voices late: the speech listener's
   VoicesChanged says they changed). None when speech is not available,
   or JS's list could not be read. A voice with no name is left out, as
   speech_speak could not name it. *)
#pub fun speech_voices(): $R.option([k:nat] voices(k))

(* Reads text[0, text_len) aloud, after what is queued: in language
   lang[0, lang_len) (the default when lang_len is 0), with the voice
   named voice[0, voice_len) (the default for the language when
   voice_len is 0, or no voice has that name), at rate_hundredths / 100
   of the normal speed. Speaking, with its number for the speech
   listener's events, or SpeechUnavailable. *)
#pub fun speech_speak
  {lt:agz}{nt:pos}{ll:agz}{nl:pos}{kl:nat | kl <= nl}
  {lv:agz}{nv:pos}{kv:nat | kv <= nv}{rate:int | 25 <= rate; rate <= 400}
  (text: !$A.borrow(byte, lt, nt), text_len: int nt,
   lang: !$A.borrow(byte, ll, nl), lang_len: int kl,
   voice: !$A.borrow(byte, lv, nv), voice_len: int kv,
   rate_hundredths: int rate): speech_start

(* Pauses what is being read, to go on with speech_resume *)
#pub fun speech_pause(): void

#pub fun speech_resume(): void

(* Stops what is being read, and drops what is queued (each gets
   SpeechFailed with Interrupted) *)
#pub fun speech_cancel(): void

(* The listener for speech's events, decoded here: each is passed to
   callback as a speech_event. An event bridge cannot read (JS's word
   is checked here, once) is not passed on. *)
#pub fun listen_speech
  (listener_id: listener_id,
   callback: (speech_event) -<lincloptr1> void): void

(* The sentences of text[0, text_len) (UTF-8), in language
   lang[0, lang_len) (the default when lang_len is 0), from the first
   (at 0), each with its trailing spaces. Intl.Segmenter where there is
   one; else a sentence ends after a run of . ! ? or an ellipsis, or
   their CJK forms (U+3002, U+FF01, U+FF1F), with the closing quotes
   and brackets after it and the space after those. None when they
   could not be made, or JS's offsets were not in order inside the
   text. *)
#pub fun segment_sentences
  {lt:agz}{nt:pos}{ll:agz}{nl:pos}{kl:nat | kl <= nl}
  (text: !$A.borrow(byte, lt, nt), text_len: int nt,
   lang: !$A.borrow(byte, ll, nl), lang_len: int kl)
  : $R.option([first:nat | first <= nt] sentences(nt, first))

(* The voices and sentences are freed here, outside the wasm target, so
   static code can free what it is given *)
implement voices_free(v) = let
  fn lang_free (lang: voice_lang): void =
    case+ lang of
    | ~NoLanguage() => ()
    | ~Language(a, _) => $A.free<byte>(a)
  fun loop {k:nat} .<k>. (v: voices(k)): void =
    case+ v of
    | ~VoicesEnd() => ()
    | ~VoicesMore(one, rest) => let
        val+ ~Voice(name, _, lang, _) = one
        val () = $A.free<byte>(name)
        val () = lang_free(lang)
      in loop(rest) end
in loop(v) end

implement sentences_free{n,first}(s) = let
  fun loop {n,f:int | f <= n} .<n - f>. (s: sentences(n, f)): void =
    case+ s of
    | ~SentencesEnd() => ()
    | ~Sentence(_, rest) => loop(rest)
in loop(s) end

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_listener_set_decoded(int id, void *decoder, void *inner);
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

(* The int32 LE at a[at, at + 4) *)
fn _i32_at {l:agz}{n:nat}{o:nat | o + 4 <= n}
  (a: !$A.arr(byte, l, n), at: int o): int = let
  val b0 = byte2int0($A.get<byte>(a, at))
  val b1 = byte2int0($A.get<byte>(a, at + 1))
  val b2 = byte2int0($A.get<byte>(a, at + 2))
  val b3 = byte2int0($A.get<byte>(a, at + 3))
  val high = (if b3 >= 128 then b3 - 256 else b3): int
in b0 + b1 * 256 + b2 * 65536 + high * 16777216 end

(* The int32 LE at b[at, at + 4) *)
fn _blob_i32 {n:nat}{o:nat | o + 4 <= n}
  (b: !dblob(n), at: int o): int = let
  val cell = $A.alloc<byte>(4)
  val () = blob_read(b, at, cell, 4)
  val v = _i32_at(cell, 0)
  val () = $A.free<byte>(cell)
in v end

(* The byte at b[at] *)
fn _blob_byte {n:nat}{o:nat | o + 1 <= n}
  (b: !dblob(n), at: int o): int = let
  val cell = $A.alloc<byte>(1)
  val () = blob_read(b, at, cell, 1)
  val v = byte2int0($A.get<byte>(cell, 0))
  val () = $A.free<byte>(cell)
in v end

(* n bytes of b from at, in an array of their own *)
fn _blob_bytes {n:nat}{o:nat}{k:pos | o + k <= n; k <= 1048576}
  (b: !dblob(n), at: int o, k: int k): [l:agz] $A.arr(byte, l, k) = let
  val a = $A.alloc<byte>(k)
  val () = blob_read(b, at, a, k)
in a end

implement speech_available() = _bats_js_speech_available() > 0

(* JS's list: for each voice, a byte (1 when it is the default), its
   name's length (int32 LE, at least 1) and name, and its language's
   length (int32 LE) and language. Each length is checked here. *)
fun _voices_from {n:nat}{o:nat | o <= n} .<n - o>.
  (b: !dblob(n), n: int n, at: int o): Option_vt([k:nat] voices(k)) =
  if at >= n then Some_vt(VoicesEnd())
  else if at + 5 > n then None_vt()
  else let
    val is_default = _blob_byte(b, at) = 1
    val name_len = g1ofg0(_blob_i32(b, at + 1))
  in
    if name_len <= 0 then None_vt()
    else if name_len > 1048576 then None_vt()
    else if at + 5 + name_len + 4 > n then None_vt()
    else let
      val name = _blob_bytes(b, at + 5, name_len)
      val lang_at = at + 5 + name_len
      val lang_len = g1ofg0(_blob_i32(b, lang_at))
    in
      if lang_len < 0 then let val () = $A.free<byte>(name) in None_vt() end
      else if lang_len > 1048576 then let val () = $A.free<byte>(name) in None_vt() end
      else if lang_at + 4 + lang_len > n then let val () = $A.free<byte>(name) in None_vt() end
      else let
        val lang = (if lang_len = 0 then NoLanguage()
          else Language(_blob_bytes(b, lang_at + 4, lang_len), lang_len)): voice_lang
        val one = Voice(name, name_len, lang, is_default)
      in
        case+ _voices_from(b, n, lang_at + 4 + lang_len) of
        | ~Some_vt(rest) => Some_vt(VoicesMore(one, rest))
        | ~None_vt() => let
            val () = voices_free(VoicesMore(one, VoicesEnd()))
          in None_vt() end
      end
    end
  end

implement speech_voices() =
  case+ blob_claim(_bats_js_speech_voices()) of
  | ~$R.none() => $R.none()
  | ~$R.some(b) => let
      val voices = _voices_from(b, blob_len(b), 0)
      val () = blob_free(b)
    in
      case+ voices of
      | ~Some_vt(v) => $R.some(v)
      | ~None_vt() => $R.none()
    end

(* JS's word is checked here, once: its number, from 1, or 0 when speech
   is not available *)
implement speech_speak{lt}{nt}{ll}{nl}{kl}{lv}{nv}{kv}{rate}
  (text, text_len, lang, lang_len, voice, voice_len, rate_hundredths) = let
  val u = _bats_js_speech_speak(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(text) end, text_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(lang) end, lang_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(voice) end, voice_len,
    rate_hundredths)
in if u > 0 then Speaking(u) else SpeechUnavailable() end

implement speech_pause() = _bats_js_speech_control(0)

implement speech_resume() = _bats_js_speech_control(1)

implement speech_cancel() = _bats_js_speech_control(2)

(* JS's failure codes: 1 interrupted or cancelled, 2 not allowed, 3 no
   such language or voice, any other OtherFailure *)
fn _speech_failure (code: int): speech_failure =
  if code = 1 then Interrupted()
  else if code = 2 then NotAllowed()
  else if code = 3 then NoSuchVoice()
  else OtherFailure()

(* JS's event: 9 bytes, its kind (0 started, 1 a boundary, 2 ended, 3
   failed, 4 the voices changed), the utterance's number (int32 LE; 0
   for 4) and a value (int32 LE): a boundary's offset, a failure's code.
   Anything else is not an event. *)
fn _speech_event (payload: event_payload): Option_vt(speech_event) =
  case+ blob_claim(payload) of
  | ~$R.none() => None_vt()
  | ~$R.some(b) =>
    if blob_len(b) < 9 then let val () = blob_free(b) in None_vt() end
    else let
      val bytes = $A.alloc<byte>(9)
      val () = blob_read(b, 0, bytes, 9)
      val () = blob_free(b)
      val kind = byte2int0($A.get<byte>(bytes, 0))
      val u = g1ofg0(_i32_at(bytes, 1))
      val v = g1ofg0(_i32_at(bytes, 5))
      val () = $A.free<byte>(bytes)
    in
      if kind = 4 then Some_vt(VoicesChanged())
      else if u <= 0 then None_vt()
      else if kind = 0 then Some_vt(SpeechStarted(u))
      else if kind = 1 then
        (if v >= 0 then Some_vt(SpeechBoundary(u, v)) else None_vt())
      else if kind = 2 then Some_vt(SpeechEnded(u))
      else if kind = 3 then Some_vt(SpeechFailed(u, _speech_failure(v)))
      else None_vt()
    end

(* The slot holds the decoder and the callback, and frees both (the
   decoder holds only the callback's pointer) *)
implement listen_speech(listener_id, callback) = let
  val inner = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val decode = llam (payload: event_payload): int =<lincloptr1>
    case+ _speech_event(payload) of
    | ~Some_vt(event) => let
        val call = $UNSAFE begin $UNSAFE.cast{(speech_event) -<cloref1> void}(inner) end
        val () = call(event)
      in 0 end
    | ~None_vt() => 0
  val decoder = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(decode) end
  val () = $UNSAFE begin
    $extfcall(void, "bats_listener_set_decoded", listener_id, decoder, inner) end
in _bats_js_listen_speech(listener_id) end

(* JS's starts: int32 LE, in order. They are checked from the last back,
   each before the one after it and not below 0, so the list is built
   in order without recursion's depth. *)
fun _starts_from
  {nt:pos}{m:nat}{l:agz}{p:int | 0 <= p + 4; p + 4 <= m}{t:nat | t <= nt} .<p + 4>.
  (a: !$A.arr(byte, l, m), at: int p, next: int t, acc: sentences(nt, t))
  : Option_vt([first:nat | first <= nt] sentences(nt, first)) =
  if at < 0 then Some_vt(acc)
  else let
    val s = g1ofg0(_i32_at(a, at))
  in
    if s < 0 then let val () = sentences_free(acc) in None_vt() end
    else if s >= next then let val () = sentences_free(acc) in None_vt() end
    else _starts_from(a, at - 4, s, Sentence(s, acc))
  end

implement segment_sentences{lt}{nt}{ll}{nl}{kl}(text, text_len, lang, lang_len) = let
  val handle = _bats_js_segment_sentences(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(text) end, text_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(lang) end, lang_len)
in
  case+ blob_claim(handle) of
  | ~$R.none() => $R.none()
  | ~$R.some(b) => let
      val n = blob_len(b)
    in
      if n <= 0 then let val () = blob_free(b) in $R.none() end
      else if n > 1048576 then let val () = blob_free(b) in $R.none() end
      else if n mod 4 <> 0 then let val () = blob_free(b) in $R.none() end
      else if n < 4 then let val () = blob_free(b) in $R.none() end
      else let
        val starts = $A.alloc<byte>(n)
        val () = blob_read(b, 0, starts, n)
        val () = blob_free(b)
        val found = _starts_from(starts, n - 4, text_len, SentencesEnd())
        val () = $A.free<byte>(starts)
      in
        case+ found of
        | ~Some_vt(s) => $R.some(s)
        | ~None_vt() => $R.none()
      end
    end
end

end (* #target wasm *)
