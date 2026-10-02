#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use gestures as G
#use wasm.bats-packages.dev/bridge as B
staload "gestures/src/consts.sats"
staload "gestures/src/pointer.sats"
staload "gestures/src/tracker.sats"
staload "gestures/src/decode.sats"
staload "gestures/src/source.sats"
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload EV = "wasm.bats-packages.dev/bridge/src/event.bats"
staload TI = "wasm.bats-packages.dev/bridge/src/timer.bats"
staload WI = "wasm.bats-packages.dev/bridge/src/window.bats"

(* The pointer atoms wired to the gestures package's pointer source, as
   an app does: each raw record goes to gestures_raw, each frame asked
   for to gestures_frame, and each capture asked for to pointer_capture;
   every gesture event is logged *)

(* s's bytes in a fresh array of exactly its length *)
fn bytes {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

fn say {n:pos | n < 256} (line: string n): void = let
  val n = g1u2i(string1_length(line))
  val @(frozen, borrowed) = $A.freeze<byte>(bytes(line))
  val () = $WI.log($WI.Info(), borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fun show {n:nat} .<n>. (es: list_vt(gevent, n)): void =
  case+ es of
  | ~list_vt_nil() => ()
  | ~list_vt_cons(e, rest) => let
      val () = (case+ e of
        | ~GPan(_, _) => say("pan")
        | ~GCommit(_, _) => say("commit")
        | ~GCancel(_, _) => say("cancel")
        | ~GLongPress(_, _, _) => say("long-press")
        | ~GPinch(_, _, _, _) => say("pinch")
        | ~GPinchEnd(_) => say("pinch-end")
        | ~GScrollEnd(_, _) => say("scrollend")
        | ~GTransitionEnd(_) => say("transitionend")
        | ~GTransitionCancel(_) => say("transitioncancel"))
    in show(rest) end

(* The recognizer and the source, kept between events *)
datavtype held = Held of (gstate, source) | Nothing
val _held = ref<held>(Nothing())

fn take (): held = let
  var cell: held = Nothing()
  val () = ref_exch_elt<held>(_held, cell)
in cell end

fn give (h: held): void = let
  var cell: held = h
  val () = ref_exch_elt<held>(_held, cell)
in case+ cell of ~Nothing() => () | ~Held(st, src) => let
    val () = gestures_source_free(src) in gestures_free(st) end end

(* Does what the source asks: a capture, or a frame, whose time goes back
   to the source. Frames ask for frames while a pointer is down, so the
   chain has fuel: a metric needs a bound *)
fun act {n:nat}{fuel:nat} .<fuel, n + 1>. (xs: list_vt(action, n), fuel: int fuel): void =
  case+ xs of
  | ~list_vt_nil() => ()
  | ~list_vt_cons(x, rest) => let
      val () = (case+ x of
        | ~CapturePointer(id) => let
            val () = say("capture")
            val @(frozen, root) = $A.freeze<byte>(bytes("bats-root"))
            val () = $EV.pointer_capture(root, 9, id)
            val () = $A.drop<byte>(frozen, root)
          in $A.free<byte>($A.thaw<byte>(frozen)) end
        | ~WantFrame() => $P.finish<Int>($TI.animation_frame(), llam (t) => on_frame(gestures_stamp(t), fuel)))
    in act(rest, fuel) end

and on_frame {fuel:nat} .<fuel, 0>. (t: stamp, fuel: int fuel): void =
  if fuel <= 0 then ()
  else case+ take() of
  | ~Held(st, src) => let
      val @(events, asked) = gestures_frame(src, st, t)
      val () = give(Held(st, src))
      val () = show(events)
    in act(asked, fuel - 1) end
  | ~Nothing() => ()

fn on_raw (payload: $EV.event_payload): void =
  case+ $EV.event_take(payload) of
  | ~$R.none() => ()
  | ~$R.some(blob) => let
      val k = $DC.blob_len(blob)
    in
      if k >= 48 then (if k <= 48 then let
        val b = $A.alloc<byte>(k)
        val () = $DC.blob_read(blob, 0, b, k)
        val () = $DC.blob_free(blob)
      in case+ take() of
        | ~Held(st, src) => let
            val @(events, asked) = gestures_raw(src, st, b, 0)
            val () = $A.free<byte>(b)
            val () = give(Held(st, src))
            val () = show(events)
          in act(asked, 1000) end
        | ~Nothing() => $A.free<byte>(b)
      end else $DC.blob_free(blob))
      else $DC.blob_free(blob)
    end

implement main0 () = let
  val st = gestures_new()
  val () = gestures_region(st, 1, ~1, AxH(), false, false, DevAll())
  val () = give(Held(st, gestures_source_new()))
  val @(frozen, root) = $A.freeze<byte>(bytes("bats-root"))
  val () = $EV.listen_pointer(root, 9, 0, llam (payload) => let val () = on_raw(payload) in 0 end)
  val () = $A.drop<byte>(frozen, root)
in $A.free<byte>($A.thaw<byte>(frozen)) end
