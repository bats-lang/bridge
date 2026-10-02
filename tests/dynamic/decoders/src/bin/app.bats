#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload "wasm.bats-packages.dev/bridge/src/dom.bats"
staload AU = "wasm.bats-packages.dev/bridge/src/audio.bats"
staload CL = "wasm.bats-packages.dev/bridge/src/clipboard.bats"
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.bats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.bats"
staload ID = "wasm.bats-packages.dev/bridge/src/idb.bats"
staload ME = "wasm.bats-packages.dev/bridge/src/media.bats"
staload NV = "wasm.bats-packages.dev/bridge/src/nav.bats"
staload NO = "wasm.bats-packages.dev/bridge/src/notify.bats"
staload SR = "wasm.bats-packages.dev/bridge/src/scroll.bats"
staload WI = "wasm.bats-packages.dev/bridge/src/window.bats"

(* Each answer bridge decodes is shown as a line <p id=name>what</p>
   under the root; check.mjs prints the lines in order of their names,
   since the promises' answers come in any order *)

stadef BUFFER_SIZE = 256

(* s's bytes at offset; the offset after them *)
fn put {l:agz}{offset,n:nat | offset + n <= BUFFER_SIZE}
  (buffer: !$A.arr(byte, l, BUFFER_SIZE), offset: int offset, s: string n): int(offset + n) = let
  val n = g1u2i(string1_length(s))
  val () = $A.write_text(buffer, offset, $A.text_lit(s), n)
in offset + n end

(* The line's text ends at offset, after what (what_len bytes from
   text_at); the number, if any, is written after it, the text's length
   before it, and the buffer flushed *)
fn flush_line {l:agz}{t,w:nat | t >= 2; t + w + 4 <= BUFFER_SIZE}
  (buffer: !$A.arr(byte, l, BUFFER_SIZE), offset: int (t + w), text_at: int t, what_len: int w,
   number: $R.option([v:nat | v < 1000] int v)): void =
  case+ number of
    | ~$R.some(v) => let
        val () = $A.write_byte(buffer, offset, 32)
        val hundreds = v / 100
        val rest = v - 100 * hundreds
        val tens = rest / 10
        val () = $A.write_byte(buffer, offset + 1, 48 + hundreds)
        val () = $A.write_byte(buffer, offset + 2, 48 + tens)
        val () = $A.write_byte(buffer, offset + 3, 48 + rest - 10 * tens)
        val () = $A.write_u16le(buffer, text_at - 2, what_len + 4)
      in dom_flush(buffer, offset + 4) end
    | ~$R.none() => let
        val () = $A.write_u16le(buffer, text_at - 2, what_len)
      in dom_flush(buffer, offset) end

(* A line <p id=name> under the root, whose text is what, then a space
   and number when there is one *)
fn line {ni,nw:pos | ni < 32; nw < 32}
  (name: string ni, what: string nw, number: $R.option([v:nat | v < 1000] int v)): void = let
  val buffer = $A.alloc<byte>(256)
  val name_len = g1u2i(string1_length(name))
  val what_len = g1u2i(string1_length(what))
  (* CREATE_ELEMENT (4): [4][id][parent][tag] *)
  val () = $A.write_byte(buffer, 0, 4)
  val () = $A.write_u16le(buffer, 1, name_len)
  val offset = put(buffer, 3, name)
  val () = $A.write_u16le(buffer, offset, 9)
  val offset = put(buffer, offset + 2, "bats-root")
  val () = $A.write_byte(buffer, offset, 1)
  val offset = put(buffer, offset + 1, "p")
  (* SET_TEXT (1): [1][id][text] *)
  val () = $A.write_byte(buffer, offset, 1)
  val () = $A.write_u16le(buffer, offset + 1, name_len)
  val offset = put(buffer, offset + 3, name)
  val text_at = offset + 2
  val offset = put(buffer, text_at, what)
  val () = flush_line(buffer, offset, text_at, what_len, number)
in $A.free<byte>(buffer) end

fn say {ni,nw:pos | ni < 32; nw < 32} (name: string ni, what: string nw): void =
  line(name, what, $R.none())

(* A number shown when it is under 1000, which every one here is *)
fn count {ni,nw:pos | ni < 32; nw < 32}{v:nat} (name: string ni, what: string nw, v: int v): void =
  if v < 1000 then line(name, what, $R.some(v)) else say(name, "too large")

(* A frozen copy of s, to pass as a borrow *)
fn bytes {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

fn show_lookup {ni:pos | ni < 32} (name: string ni, found: $ID.lookup): void =
  case+ found of
  | ~$ID.Found(blob) => let
      val () = count(name, "found", $DC.blob_len(blob))
    in $DC.blob_free(blob) end
  | ~$ID.Absent() => say(name, "absent")
  | ~$ID.Unreadable() => say(name, "unreadable")

fn show_stored {ni:pos | ni < 32} (name: string ni, outcome: $ID.stored): void =
  case+ outcome of
  | $ID.Stored() => say(name, "stored")
  | $ID.NotStored() => say(name, "not stored")

fn show_play {ni:pos | ni < 32} (name: string ni, outcome: $AU.play_outcome): void =
  case+ outcome of
  | $AU.Playing() => say(name, "playing")
  | $AU.PlayRefused() => say(name, "refused")
  | $AU.Unplayable() => say(name, "unplayable")

fn show_permission {ni:pos | ni < 32} (name: string ni, answer: $NO.permission): void =
  case+ answer of
  | $NO.Granted() => say(name, "granted")
  | $NO.Denied() => say(name, "denied")
  | $NO.NotAsked() => say(name, "not asked")

fn show_measured {ni:pos | ni < 32} (name: string ni, outcome: $DR.measured): void =
  case+ outcome of
  | $DR.Measured() => say(name, "measured")
  | $DR.NoElement() => say(name, "no element")

fn show_media {ni:pos | ni < 32} (name: string ni, outcome: $ME.media_match): void =
  case+ outcome of
  | $ME.Matches() => say(name, "matches")
  | $ME.NoMatch() => say(name, "no match")

fn show_time {ni:pos | ni < 32} (name: string ni, time: $R.option([v:nat] int v)): void =
  case+ time of
  | ~$R.some(ms) => count(name, "ms", ms)
  | ~$R.none() => say(name, "none")

(* The reads and writes to IndexedDB: put, get, a key never put, the
   keys listed, a delete, and (check.mjs makes key "bad" fail) a read
   and a write that fail. Each waits for the one before it *)
fn storage (): void = let
  val @(key_frozen, key) = $A.freeze<byte>(bytes("k1"))
  val @(value_frozen, value) = $A.freeze<byte>(bytes("v1"))
  val put_promise = $ID.idb_put(key, 2, value, 2)
  val () = $A.drop<byte>(value_frozen, value)
  val () = $A.free<byte>($A.thaw<byte>(value_frozen))
  val () = $A.drop<byte>(key_frozen, key)
  val () = $A.free<byte>($A.thaw<byte>(key_frozen))
in $P.finish<$ID.stored>(put_promise, llam (outcome) => let
  val () = show_stored("idb-1-put", outcome)
  val @(key_frozen, key) = $A.freeze<byte>(bytes("k1"))
  val @(absent_frozen, absent_key) = $A.freeze<byte>(bytes("k2"))
  val @(bad_frozen, bad_key) = $A.freeze<byte>(bytes("bad"))
  val @(start_frozen, key_start) = $A.freeze<byte>(bytes("k"))
  val () = $P.finish<$ID.lookup>($ID.idb_get(key, 2), llam (found) => show_lookup("idb-2-get", found))
  val () = $P.finish<$ID.lookup>($ID.idb_get(absent_key, 2), llam (found) => show_lookup("idb-3-get-absent", found))
  val () = $P.finish<$ID.lookup>($ID.idb_get(bad_key, 3), llam (found) => show_lookup("idb-4-get-failed", found))
  val () = $P.finish<$ID.lookup>($ID.idb_list_keys(key_start, 1), llam (found) => show_lookup("idb-5-keys", found))
  val () = $P.finish<$ID.stored>($ID.idb_put(bad_key, 3, key_start, 1), llam (outcome) => show_stored("idb-6-put-failed", outcome))
  val () = $P.finish<$ID.stored>($ID.idb_delete(absent_key, 2), llam (outcome) => show_stored("idb-7-delete", outcome))
  val () = $P.finish<$BF.file_lookup>($BF.file_idb_get(key, 2), llam (found) =>
    case+ found of
    | ~$BF.FileFound(f) => let
        val () = count("file-1-get", "found", $BF.file_size(f))
      in $BF.file_close(f) end
    | ~$BF.FileAbsent() => say("file-1-get", "absent")
    | ~$BF.FileUnreadable() => say("file-1-get", "unreadable"))
  val () = $P.finish<$BF.file_lookup>($BF.file_idb_get(absent_key, 2), llam (found) =>
    case+ found of
    | ~$BF.FileFound(f) => $BF.file_close(f)
    | ~$BF.FileAbsent() => say("file-2-get-absent", "absent")
    | ~$BF.FileUnreadable() => say("file-2-get-absent", "unreadable"))
  val () = $P.finish<$BF.file_lookup>($BF.file_idb_get(bad_key, 3), llam (found) =>
    case+ found of
    | ~$BF.FileFound(f) => $BF.file_close(f)
    | ~$BF.FileAbsent() => say("file-3-get-failed", "absent")
    | ~$BF.FileUnreadable() => say("file-3-get-failed", "unreadable"))
  val () = $A.drop<byte>(start_frozen, key_start)
  val () = $A.free<byte>($A.thaw<byte>(start_frozen))
  val () = $A.drop<byte>(bad_frozen, bad_key)
  val () = $A.free<byte>($A.thaw<byte>(bad_frozen))
  val () = $A.drop<byte>(absent_frozen, absent_key)
  val () = $A.free<byte>($A.thaw<byte>(absent_frozen))
  val () = $A.drop<byte>(key_frozen, key)
in $A.free<byte>($A.thaw<byte>(key_frozen)) end) end

implement main0 () = let
  (* an element to measure and scroll to, with a text *)
  val () = say("element", "text")
  val @(element_frozen, element) = $A.freeze<byte>(bytes("element"))
  val @(missing_frozen, missing) = $A.freeze<byte>(bytes("missing"))
  val () = (case+ $WI.get_visibility() of
    | $WI.Visible() => say("visibility-1", "visible")
    | $WI.Hidden() => say("visibility-1", "hidden"))
  val @(wide_frozen, wide) = $A.freeze<byte>(bytes("(min-width: 1px)"))
  val @(print_frozen, print_query) = $A.freeze<byte>(bytes("print"))
  val () = show_media("media-1", $ME.match_media(wide, 16))
  val () = show_media("media-2", $ME.match_media(print_query, 5))
  (* check.mjs fires a change with matches false, once it has hidden
     the page *)
  val () = $ME.listen_media(wide, 16, 3, llam (outcome) => let
    val () = show_media("media-3-change", outcome)
    val () = (case+ $WI.get_visibility() of
      | $WI.Visible() => say("visibility-2", "visible")
      | $WI.Hidden() => say("visibility-2", "hidden"))
  in 0 end)
  val () = $A.drop<byte>(print_frozen, print_query)
  val () = $A.free<byte>($A.thaw<byte>(print_frozen))
  val () = $A.drop<byte>(wide_frozen, wide)
  val () = $A.free<byte>($A.thaw<byte>(wide_frozen))
  val () = show_measured("measure-1", $DR.measure(element, 7))
  val () = show_measured("measure-2", $DR.measure(missing, 7))
  val () = show_measured("measure-3-text", $DR.measure_text_offset(element, 7, 2))
  val () = show_measured("measure-4-text", $DR.measure_text_offset(missing, 7, 2))
  val () = (case+ $DR.caret_position_from_point(10, 10) of
    | ~$R.some(offset) => count("caret-1", "offset", offset)
    | ~$R.none() => say("caret-1", "none"))
  val () = (case+ $DR.caret_position_from_point(~1, ~1) of
    | ~$R.some(offset) => count("caret-2", "offset", offset)
    | ~$R.none() => say("caret-2", "none"))
  val url = $A.alloc<byte>(64)
  val () = count("url-1", "length", $NV.get_url(url, 64))
  val () = $A.free<byte>(url)
  val url = $A.alloc<byte>(5)
  val () = count("url-2-cut", "length", $NV.get_url(url, 5))
  val () = $A.free<byte>(url)
  val hash = $A.alloc<byte>(64)
  val () = count("url-3-hash", "length", $NV.get_hash(hash, 64))
  val () = $A.free<byte>(hash)
  val () = $SR.scroll_into_view(element, 7, $SR.Smooth())
  val () = $SR.scroll_into_view(element, 7, $SR.Instant())
  val @(message_frozen, message) = $A.freeze<byte>(bytes("hello"))
  val () = $WI.log($WI.Warn(), message, 5)
  val () = $WI.log($WI.Error(), message, 5)
  val () = $A.drop<byte>(message_frozen, message)
  val () = $A.free<byte>($A.thaw<byte>(message_frozen))
  (* audio: none, one that plays, one the browser refuses *)
  val () = say("player", "audio")
  val () = say("refusing", "audio")
  val @(player_frozen, player) = $A.freeze<byte>(bytes("player"))
  val @(refusing_frozen, refusing) = $A.freeze<byte>(bytes("refusing"))
  val () = show_time("audio-1-time", $AU.audio_time(player, 6))
  val () = show_time("audio-2-time", $AU.audio_time(missing, 7))
  val () = $P.finish<$AU.play_outcome>($AU.audio_play(player, 6), llam (outcome) => show_play("audio-3-play", outcome))
  val () = $P.finish<$AU.play_outcome>($AU.audio_play(refusing, 8), llam (outcome) => show_play("audio-4-play", outcome))
  val () = $P.finish<$AU.play_outcome>($AU.audio_play(missing, 7), llam (outcome) => show_play("audio-5-play", outcome))
  val () = $A.drop<byte>(refusing_frozen, refusing)
  val () = $A.free<byte>($A.thaw<byte>(refusing_frozen))
  val () = $A.drop<byte>(player_frozen, player)
  val () = $A.free<byte>($A.thaw<byte>(player_frozen))
  (* the clipboard: check.mjs refuses the text "no" *)
  val @(yes_frozen, yes) = $A.freeze<byte>(bytes("yes"))
  val @(no_frozen, no) = $A.freeze<byte>(bytes("no"))
  val () = $P.finish<$CL.copied>($CL.clipboard_write(yes, 3), llam (outcome) =>
    case+ outcome of
    | $CL.Copied() => say("clipboard-1", "copied")
    | $CL.NotCopied() => say("clipboard-1", "not copied"))
  val () = $P.finish<$CL.copied>($CL.clipboard_write(no, 2), llam (outcome) =>
    case+ outcome of
    | $CL.Copied() => say("clipboard-2", "copied")
    | $CL.NotCopied() => say("clipboard-2", "not copied"))
  val () = $A.drop<byte>(no_frozen, no)
  val () = $A.free<byte>($A.thaw<byte>(no_frozen))
  val () = $A.drop<byte>(yes_frozen, yes)
  val () = $A.free<byte>($A.thaw<byte>(yes_frozen))
  (* notifications: check.mjs answers granted, then default, then denied *)
  val () = $P.finish<$NO.permission>($NO.notify_request_permission(), llam (answer) => let
    val () = show_permission("permission-1", answer)
  in $P.finish<$NO.permission>($NO.notify_request_permission(), llam (answer) => let
    val () = show_permission("permission-2", answer)
  in $P.finish<$NO.permission>($NO.notify_request_permission(), llam (answer) =>
    show_permission("permission-3", answer)) end) end)
  (* decompression: stored bytes come back as they are, and raw deflate
     of bytes that are not deflate fails (so the method reached JS) *)
  val @(plain_frozen, plain) = $A.freeze<byte>(bytes("abc"))
  val @(decompressed, resolver) = $P.create<Int>()
  val () = $DC.decompress_req(plain, 3, $DC.Uncompressed(), $P.stash(resolver))
  val () = $P.finish<Int>(decompressed, llam (handle) =>
    case+ $DC.blob_claim(handle) of
    | ~$R.some(blob) => let
        val () = count("decompress-1-stored", "bytes", $DC.blob_len(blob))
      in $DC.blob_free(blob) end
    | ~$R.none() => say("decompress-1-stored", "failed"))
  val @(failed, resolver) = $P.create<Int>()
  val () = $DC.decompress_req(plain, 3, $DC.DeflateRaw(), $P.stash(resolver))
  val () = $P.finish<Int>(failed, llam (handle) =>
    case+ $DC.blob_claim(handle) of
    | ~$R.some(blob) => let
        val () = count("decompress-2-raw", "bytes", $DC.blob_len(blob))
      in $DC.blob_free(blob) end
    | ~$R.none() => say("decompress-2-raw", "failed"))
  val () = $A.drop<byte>(plain_frozen, plain)
  val () = $A.free<byte>($A.thaw<byte>(plain_frozen))
  val () = storage()
  val () = $A.drop<byte>(missing_frozen, missing)
  val () = $A.free<byte>($A.thaw<byte>(missing_frozen))
  val () = $A.drop<byte>(element_frozen, element)
in $A.free<byte>($A.thaw<byte>(element_frozen)) end
