(* stash -- the root node's id, handed over by JS for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* The root element's HTML id, as a blob *)
#pub fun get_root_node(): $R.option([k:nat] dblob(k))

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

(* JS's code for a blob, as a handle: bridge's own atoms are the only
   ones that give one *)
fn _claimed_blob (code: int): $R.option([n:nat] dblob(n)) =
  blob_claim($UNSAFE begin $UNSAFE.cast{blob_handle}(code) end)

$UNSAFE begin
%{
extern int bats_js_get_root_node(void);
%}
extern fun _bats_js_get_root_node
  (): [v:int] int v = "mac#bats_js_get_root_node"
end

implement get_root_node() = _claimed_blob(_bats_js_get_root_node())

end (* #target wasm *)
