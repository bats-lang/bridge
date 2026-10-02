(* An atom's JS naming a plugin itself, not through the table: the
   plugin-names check must reject it *)
fn emit_js_camera {n:nat | n + 80 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 80] $B.builder(m)): void =
  $B.bput(b,"  function batsJsCameraAvailable() { return capPlugin('Camera') ? 1 : 0; }\n")
