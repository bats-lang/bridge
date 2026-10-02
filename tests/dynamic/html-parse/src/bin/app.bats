#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload WI = "wasm.bats-packages.dev/bridge/src/window.bats"
staload XM = "wasm.bats-packages.dev/bridge/src/xml.bats"

(* Parses HTML with an event handler, a style, a script and an iframe,
   and logs the raw stream xml_parse gives: all of it is there (what is
   kept is the html package's) *)
implement main0 () = let
  val bytes = $A.alloc<byte>(62)
  val () = $A.write_text(bytes, 0, $A.text_lit("<p onclick=x style=y>a<script>b</script><iframe></iframe></p> "), 62)
  val @(frozen, borrowed) = $A.freeze<byte>(bytes)
  val () = (case+ $XM.xml_parse(borrowed, 62) of
    | ~$R.some(blob) => let
        val k = $DC.blob_len(blob)
      in
        if k > 0 then if k <= 4096 then let
          val out = $A.alloc<byte>(k)
          val () = $DC.blob_read(blob, 0, out, k)
          val () = $DC.blob_free(blob)
          val @(out_frozen, out_borrowed) = $A.freeze<byte>(out)
          val () = $WI.log($WI.Info(), out_borrowed, k)
          val () = $A.drop<byte>(out_frozen, out_borrowed)
        in $A.free<byte>($A.thaw<byte>(out_frozen)) end
        else $DC.blob_free(blob) else $DC.blob_free(blob)
      end
    | ~$R.none() => ())
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end
