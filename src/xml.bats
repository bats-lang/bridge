(* xml -- HTML/XML parsing for bridge *)

#include "share/atspre_staload.hats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

#pub fun xml_parse
  {lb:agz}{n:pos}
  (html: !$A.borrow(byte, lb, n), len: int n): int

#pub fun xml_result
  {n:pos | n <= 1048576}
  (len: int n): [l:agz] $A.arr(byte, l, n)

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin

extern fun _bats_js_parse_html
  (html: ptr, len: int): int = "mac#bats_js_parse_html"

implement xml_parse{lb}{n}(html, len) =
  _bats_js_parse_html(
    $UNSAFE.castvwtp1{ptr}(html),
    len)

implement xml_result{n}(len) =
  stash_read(stash_get_int(1), len)

end (* $UNSAFE *)
end (* #target wasm *)
