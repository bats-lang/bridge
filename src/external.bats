(* external -- files handed to the app from outside it, for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"
staload "./file.bats"
staload "./fetch.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* A file handed to the app from outside it: by the native app (an
   Android intent to open or share a file: batsNative.deliverFile, a URL
   its web view can fetch, fetched here), by the system that opens the
   installed web app with it (a manifest's file_handlers, through
   launchQueue), or shared with it (a manifest's share_target, kept by
   the service worker). Linear: External holds a file JS keeps until it
   is closed, and its name; one no consumer takes is freed by promise's
   dispose. *)
#pub datavtype external =
  | External of ([n:nat] infile(n), $R.option([k:nat] dblob(k)))  (* the file, its name when it has one *)
  | ExternalUnreadable of ($R.option([k:nat] dblob(k)))          (* handed at a URL that could not be
                                                                    fetched (not found, refused): its name *)

(* The next file handed to the app, in the order they came: at once when
   one is waiting (files that come before the app asks are kept), else
   when one comes. What to do with each, and asking for the next, is the
   app's *)
#pub fun external_next(): $P.promise(external, $P.Chained)

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_js_external_next(int);
extern int bats_js_external_url(int);
extern int bats_js_external_name(int);
%}
extern fun _bats_js_external_next
  (resolver_id: int): void = "mac#bats_js_external_next"
extern fun _bats_js_external_url
  (key: int): [v:int] int v = "mac#bats_js_external_url"
extern fun _bats_js_external_name
  (key: int): [v:int] int v = "mac#bats_js_external_name"
end

fn _name_free (name: $R.option([k:nat] dblob(k))): void =
  case+ name of
  | ~$R.some(b) => blob_free(b)
  | ~$R.none() => ()

(* A file nobody took: closed, its name freed. Before external_next, its
   first use. *)
implement $P.dispose<external>(found) =
  case+ found of
  | ~External(f, name) => let val () = file_close(f) in _name_free(name) end
  | ~ExternalUnreadable(name) => _name_free(name)

(* A URL's bytes, as an array of exactly its length; none when it is
   empty or over 64 KiB *)
datavtype url_bytes =
  | {l:agz}{n:pos | n < 65536} UrlBytes of ($A.arr(byte, l, n), int n)
  | NoUrl

fn _url_bytes (key: int): url_bytes =
  case+ blob_claim(_bats_js_external_url(key)) of
  | ~$R.none() => NoUrl()
  | ~$R.some(blob) => let
      val n = blob_len(blob)
    in
      if n <= 0 then let val () = blob_free(blob) in NoUrl() end
      else if n >= 65536 then let val () = blob_free(blob) in NoUrl() end
      else let
        val bytes = $A.alloc<byte>(n)
        val () = blob_read(blob, 0, bytes, n)
        val () = blob_free(blob)
      in UrlBytes(bytes, n) end
    end

(* A file handed at a URL: fetched (its bytes stay on the JS side, as a
   file); unreadable when the response is not a success *)
fn _fetched (key: int): $P.promise(external, $P.Chained) = let
  (* the URL first: reading the name lets JS forget the delivery *)
  val url_read = _url_bytes(key)
  val name = blob_claim(_bats_js_external_name(key))
in
  case+ url_read of
  | ~NoUrl() => $P.ret<external>(ExternalUnreadable(name))
  | ~UrlBytes(bytes, n) => let
      val @(frozen, url) = $A.freeze<byte>(bytes)
      val asked = fetch(url, n)
      val () = $A.drop<byte>(frozen, url)
      val () = $A.free<byte>($A.thaw<byte>(frozen))
    in $P.and_then<Int><external>($P.vow(asked), llam (handle) =>
      case+ fetch_claim_file(handle) of
      | ~$R.none() => $P.ret<external>(ExternalUnreadable(name))
      | ~$R.some(@(status, f)) =>
        if status >= 200 && status < 300 then $P.ret<external>(External(f, name))
        else let val () = file_close(f) in $P.ret<external>(ExternalUnreadable(name)) end)
    end
end

(* JS's codes: a pending file's handle (positive), or the key of a URL
   to fetch (below 0). A handle JS did not hand out is unreadable *)
implement external_next() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_external_next(id)
in $P.and_then<Int><external>($P.vow(p), llam (code) =>
  if code < 0 then _fetched(~code)
  else (case+ file_claim(code) of
    | ~$R.some(f) => let
        val name = file_name(f)
      in $P.ret<external>(External(f, name)) end
    | ~$R.none() => $P.ret<external>(ExternalUnreadable($R.none())))) end

end (* #target wasm *)
