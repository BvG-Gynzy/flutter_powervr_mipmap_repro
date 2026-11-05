#!/usr/bin/env bash
# Builds the repro with the last good and the first bad Flutter version into
# build/site/<version>/, plus an index page linking all test variants.
# Serve with: python3 -m http.server 8080 --directory build/site
# Set BASE_PATH when the site is not served from the root, e.g.
# BASE_PATH=/flutter_powervr_mipmap_repro for GitHub Pages.
set -euo pipefail
cd "$(dirname "$0")"

versions=(3.41.7 3.47.5)
base_path="${BASE_PATH:-}"
rm -rf build/site
mkdir -p build/site

for version in "${versions[@]}"; do
  flutter="$HOME/.asdf/installs/flutter/$version/bin/flutter"
  "$flutter" pub get
  "$flutter" build web --release \
    --base-href "$base_path/$version/" \
    --output "build/site/$version"
done

{
  echo '<!doctype html><meta charset="utf-8"><title>PowerVR mipmap repro</title><ul>'
  for version in "${versions[@]}"; do
    echo "<li>Flutter $version: <a href=\"$version/\">default</a> · <a href=\"$version/?noMipmaps=1\">mipmaps disabled</a> · <a href=\"$version/?mipGeneration=skip\">generateMipmap skipped (A)</a> · <a href=\"$version/?mipGeneration=finish\">gl.finish() before generateMipmap (B)</a></li>"
  done
  echo '</ul><p>Add <code>&amp;cycle=0</code> (or <code>?cycle=0</code>) to stay on the first background.</p>'
  echo '<p><a href="mip_probe.html">WebGL2 mipmapped-copy probe</a>: the same GL calls without Flutter or Skia (from <a href="https://github.com/flutter/flutter/issues/194283#issuecomment-6641017256">flutter/flutter#194283</a>).</p>'
  cat <<'HTML'
<h2>Recorded runs on this device</h2>
<p>Each page load records what it did in <code>localStorage</code>, so it survives a black screen. Newest first. <button id="clear">Clear</button></p>
<pre id="runs">No runs recorded.</pre>
<script>
  function show() {
    let runs = [];
    try { runs = JSON.parse(localStorage.getItem("repro_runs") || "[]"); } catch (e) {}
    if (runs.length) {
      document.getElementById("runs").textContent = runs.slice().reverse().map((run) =>
        `${run.startedAt}  ${run.url}\n` +
        `  generateMipmap calls: ${run.generateMipmapCalls}, mipmapped allocations: ${run.mipmappedAllocations.length}\n` +
        (run.events || []).map((event) => `  ${event}`).join("\n")).join("\n\n");
    }
  }
  document.getElementById("clear").onclick = () => {
    try { localStorage.removeItem("repro_runs"); } catch (e) {}
    location.reload();
  };
  show();
</script>
HTML
} > build/site/index.html
cp mip_probe.html build/site/
touch build/site/.nojekyll

echo "Built into build/site. Serve with: python3 -m http.server 8080 --directory build/site"
