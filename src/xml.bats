(* xml -- HTML/XML parsing for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* The document the browser's DOMParser makes of html, serialised raw as
   a SAX stream ([1][tag length][tag][attribute count][attributes]...,
   [2] to close, [3][length][text]), as a blob: every element, attribute
   and text it found, with nothing filtered (only names over 255 bytes
   and texts or values over 65535, which the stream cannot hold, are
   left out). What may be shown is decided by the html package
   (sanitize). None when parsing produced nothing *)
#pub fun xml_parse
  {lb:agz}{n:pos}
  (html: !$A.borrow(byte, lb, n), len: int n)
  : $R.option([k:nat] dblob(k))

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern int bats_js_parse_html(void*, int);
%}
extern fun _bats_js_parse_html
  (html: ptr, len: int): [v:int] int v = "mac#bats_js_parse_html"

implement xml_parse{lb}{n}(html, len) =
  blob_claim(_bats_js_parse_html(
    $UNSAFE.castvwtp1{ptr}(html),
    len))

end (* $UNSAFE *)
end (* #target wasm *)
