# bridge

WASM-to-JavaScript bridge for the [Bats](https://github.com/bats-lang) programming language.

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

Nor does it make an element that runs or loads code, or changes how
the page is read: `script`, `iframe`, `frame`, `object`, `embed`,
`base`, `link`, `meta`, `template`, `noscript` and `form` (in any case).
The first one refused is logged with `console.error`. The dom package's
`tag` type has no constructor for any of them
(`tests/dynamic/element-guard`).


`unsafe = true` — contains C runtime stubs for WASM host imports. The `produce_bridge` function is safe and works on both native and WASM targets. WASM-only functions are guarded with `#target wasm begin...end`.
