(* random -- cryptographic random bytes for bridge *)

#include "share/atspre_staload.hats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

(* out[0, n) := n bytes from crypto.getRandomValues, which fills at most
   65536 bytes a call *)
#pub fun random_bytes {l:agz}{n:pos | n <= 65536}
  (out: !$A.arr(byte, l, n), n: int n): void

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_js_random_bytes(void*, int);
%}
extern fun _bats_js_random_bytes
  (out: ptr, n: int): void = "mac#bats_js_random_bytes"
end

implement random_bytes{l}{n}(out, n) =
  _bats_js_random_bytes(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end, n)

end (* #target wasm *)
