#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload PL = "wasm.bats-packages.dev/bridge/src/platform.sats"

(* A reading matched in every case of the engine, the system and the shell,
   the fact of each Unexpected taken apart in every form; one let go is freed
   by platform_free *)
fn fact (fact: $PL.platform_fact): void =
  case+ fact of
  | ~$PL.PlatformFactText(blob) => $DC.blob_free(blob)
  | ~$PL.PlatformFactAbsent() => ()
  | ~$PL.PlatformFactThrew(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
  | ~$PL.PlatformFactNotText(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
  | ~$PL.PlatformFactCode(_) => ()

fn f (): void = let
  val () = (case+ $PL.platform_read() of
    | ~$PL.PlatformIs(engine, os, shell) => let
        val () = (case+ engine of
          | ~$PL.EngineBlink() => ()
          | ~$PL.EngineWebKit() => ()
          | ~$PL.EngineGecko() => ()
          | ~$PL.EngineUnexpected(_, f) => fact(f))
        val () = (case+ os of
          | ~$PL.OsAndroid() => ()
          | ~$PL.OsIos() => ()
          | ~$PL.OsIpadOs() => ()
          | ~$PL.OsMacOs() => ()
          | ~$PL.OsWindows() => ()
          | ~$PL.OsLinux() => ()
          | ~$PL.OsChromeOs() => ()
          | ~$PL.OsUnexpected(source, agent, agent_platform, navigator_platform, touch) => let
              val () = (case+ source of
                | $PL.SourceUserAgent() => ()
                | $PL.SourceUserAgentPlatform() => ()
                | $PL.SourceNavigatorPlatform() => ()
                | $PL.SourceTouchPoints() => ()
                | $PL.SourceCapacitor() => ())
              val () = fact(agent)
              val () = fact(agent_platform)
              val () = fact(navigator_platform)
            in fact(touch) end)
      in
        case+ shell of
        | ~$PL.ShellBrowser() => ()
        | ~$PL.ShellApp(system) => (case+ system of $PL.AppIos() => () | $PL.AppAndroid() => ())
        | ~$PL.ShellWebView() => ()
        | ~$PL.ShellUnexpected(_, f) => fact(f)
      end)
  val () = $PL.platform_free($PL.platform_read())
in () end
