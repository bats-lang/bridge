# bridge

WASM-to-JavaScript bridge for the [Bats](https://github.com/bats-lang) programming language.

## Features

- Provides the JavaScript runtime that loads and connects WASM modules to the DOM
- Safe `produce_bridge` function that generates the JS bridge source as string content
- WASM-only exports for DOM manipulation, timers, events, IndexedDB, navigation, etc.
- Used by the `pwa` package to embed the JS bridge in generated HTML

## Usage

```bats
#use wasm.bats-packages.dev/bridge as BR
#use builder as B

val b = $B.create()
val () = $BR.produce_bridge(b)
(* b now contains the full JS bridge source *)
```

## API

See [docs/lib.md](docs/lib.md) for the full API reference.

## Safety

The DOM flush never sets an attribute that would run script: an event
handler (a name starting with `on`, in any case), or `href`, `src`,
`action`, `formaction` or `xlink:href` with a `javascript:` value (the
URL parser's controls and spaces removed first). It logs the first one
it refuses with `console.error`. The dom package's types refuse both
already; this is defence in depth for code that writes the flush's
buffer itself (`tests/dynamic/attribute-guard`).


`unsafe = true` — contains C runtime stubs for WASM host imports. The `produce_bridge` function is safe and works on both native and WASM targets. WASM-only functions are guarded with `#target wasm begin...end`.
