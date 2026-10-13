#!/usr/bin/env bash
# Builds the repro with the last good and the first bad Flutter version into
# build/site/<version>/, plus an index page linking all test variants.
# Serve with: python3 -m http.server 8080 --directory build/site
set -euo pipefail
cd "$(dirname "$0")"

versions=(3.41.7 3.47.5)
rm -rf build/site
mkdir -p build/site

for version in "${versions[@]}"; do
  flutter="$HOME/.asdf/installs/flutter/$version/bin/flutter"
  "$flutter" pub get
  "$flutter" build web --release \
    --base-href "/$version/" \
    --output "build/site/$version"
done

{
  echo '<!doctype html><meta charset="utf-8"><title>PowerVR mipmap repro</title><ul>'
  for version in "${versions[@]}"; do
    echo "<li><a href=\"$version/\">Flutter $version</a> · <a href=\"$version/?noMipmaps=1\">Flutter $version, mipmaps disabled</a></li>"
  done
  echo '</ul>'
} > build/site/index.html

echo "Built into build/site. Serve with: python3 -m http.server 8080 --directory build/site"
