#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.bats"
staload EX = "wasm.bats-packages.dev/bridge/src/external.bats"
staload WI = "wasm.bats-packages.dev/bridge/src/window.bats"

(* Asks for the files handed to the app, one after another, and logs
   each: its name, then whether it could be read and its size *)

fn say {n:pos | n < 256} (line: string n): void = let
  val n = g1u2i(string1_length(line))
  val bytes = $A.alloc<byte>(n)
  val () = $A.write_text(bytes, 0, $A.text_lit(line), n)
  val @(frozen, borrowed) = $A.freeze<byte>(bytes)
  val () = $WI.log($WI.Info(), borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

(* Logs a name, read from its blob *)
fn say_name (name: $R.option([k:nat] $DC.dblob(k))): void =
  case+ name of
  | ~$R.none() => say("(no name)")
  | ~$R.some(blob) => let
      val k = $DC.blob_len(blob)
    in
      if k > 0 then (if k < 256 then let
        val bytes = $A.alloc<byte>(k)
        val () = $DC.blob_read(blob, 0, bytes, k)
        val () = $DC.blob_free(blob)
        val @(frozen, borrowed) = $A.freeze<byte>(bytes)
        val () = $WI.log($WI.Info(), borrowed, k)
        val () = $A.drop<byte>(frozen, borrowed)
      in $A.free<byte>($A.thaw<byte>(frozen)) end
      else $DC.blob_free(blob))
      else $DC.blob_free(blob)
    end

fun next {left:nat} .<left>. (left: int left): void =
  if left <= 0 then ()
  else $P.finish<$EX.external>($EX.external_next(), llam (found) => let
    val () = (case+ found of
      | ~$EX.External(f, name) => let
          val () = say_name(name)
          val size = $BF.file_size(f)
          val () = $BF.file_close(f)
        in if size = 3 then say("read, 3 bytes") else say("read") end
      | ~$EX.ExternalUnreadable(name) => let
          val () = say_name(name)
        in say("unreadable") end)
  in next(left - 1) end)

implement main0 () = next(3)
