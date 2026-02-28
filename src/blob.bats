(* blob -- blob URL creation, revocation, download for bridge *)

#include "share/atspre_staload.hats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

#pub fun create_blob_url
  {ld:agz}{nd:pos}{lm:agz}{nm:pos}
  (data: !$A.borrow(byte, ld, nd), data_len: int nd,
   mime: !$A.borrow(byte, lm, nm), mime_len: int nm): int

#pub fun create_blob_url_get
  {n:pos | n <= 1048576}
  (len: int n): [l:agz] $A.arr(byte, l, n)

#pub fun revoke_blob_url
  {lb:agz}{n:pos}
  (url: !$A.borrow(byte, lb, n), url_len: int n): void

#pub fun download_blob
  {ld:agz}{nd:pos}{lm:agz}{nm:pos}{ln:agz}{nn:pos}
  (data: !$A.borrow(byte, ld, nd), data_len: int nd,
   mime: !$A.borrow(byte, lm, nm), mime_len: int nm,
   name: !$A.borrow(byte, ln, nn), name_len: int nn): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

extern fun _bats_js_create_blob_url
  (data: ptr, data_len: int, mime: ptr, mime_len: int): int
  = "mac#bats_js_create_blob_url"
extern fun _bats_js_revoke_blob_url
  (url: ptr, url_len: int): void = "mac#bats_js_revoke_blob_url"
extern fun _bats_js_download_blob
  (data: ptr, data_len: int, mime: ptr, mime_len: int,
   name: ptr, name_len: int): void = "mac#bats_js_download_blob"

implement create_blob_url{ld}{nd}{lm}{nm}(data, data_len, mime, mime_len) =
  _bats_js_create_blob_url(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end, data_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(mime) end, mime_len)

implement create_blob_url_get{n}(len) =
  stash_read(stash_get_int(1), len)

implement revoke_blob_url{lb}{n}(url, url_len) =
  _bats_js_revoke_blob_url(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end, url_len)

implement download_blob{ld}{nd}{lm}{nm}{ln}{nn}
  (data, data_len, mime, mime_len, name, name_len) =
  _bats_js_download_blob(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end, data_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(mime) end, mime_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(name) end, name_len)

end (* #target wasm *)
