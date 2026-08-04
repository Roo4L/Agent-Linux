#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/make-site-icons.sh — rasterise the house mascot into the two icon
# formats that cannot be served as SVG:
#
#   site/favicon.ico              legacy browsers (16x16 + 32x32)
#   site/assets/apple-touch-icon.png  iOS home-screen bookmarks (180x180)
#
# Both are rendered FROM site/assets/favicon.svg, which is the single source of
# truth for the house mark — so the rasters cannot drift from the SVG. Edit the
# SVG, re-run this, commit all three.
#
# Requires librsvg2-bin (rsvg-convert) and imagemagick (convert). They are
# needed only to regenerate; the outputs are committed, so neither CI nor the
# website build depends on them.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

readonly SRC=site/assets/favicon.svg
readonly ICO=site/favicon.ico
readonly APPLE=site/assets/apple-touch-icon.png

# iOS composites home-screen icons onto black and applies its own rounded-rect
# mask, so the icon must be opaque and needs a margin to survive the corners.
readonly APPLE_PX=180
readonly APPLE_ART_PX=160
readonly BG='#0A0A0A'

# ImageMagick otherwise bakes the current time into the PNG, so every re-run
# would produce a different blob and the committed icon would churn in git for
# no visual change. Pinning the epoch makes regeneration byte-reproducible.
export SOURCE_DATE_EPOCH=0

for tool in rsvg-convert convert; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "ERROR: '$tool' not found. Install with:" >&2
    echo "  sudo apt-get install -y librsvg2-bin imagemagick   # Debian/Ubuntu" >&2
    echo "  sudo dnf install -y librsvg2-tools ImageMagick     # AlmaLinux/RHEL" >&2
    exit 1
  }
done

[ -s "$SRC" ] || { echo "ERROR: $SRC missing or empty." >&2; exit 1; }

# Staged inside the repo, not $TMPDIR: the final step replaces the committed
# icons with `mv`, and that is only an atomic rename when source and destination
# share a filesystem. A system temp dir on tmpfs or its own partition would
# silently degrade it to copy-then-unlink.
tmp=$(mktemp -d "$repo_root/.site-icons.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# Multi-size ICO: browsers pick the best fit rather than downscaling one bitmap.
# The SVG's viewBox is 16 units, so 16 and 32 are exact integer scales — the
# pixel art stays crisp with no resampling artefacts.
for px in 16 32; do
  rsvg-convert -w "$px" -h "$px" "$SRC" -o "$tmp/icon-$px.png"
done
convert "$tmp/icon-16.png" "$tmp/icon-32.png" "$tmp/out.ico"

rsvg-convert -w "$APPLE_ART_PX" -h "$APPLE_ART_PX" "$SRC" -o "$tmp/apple-art.png"
convert "$tmp/apple-art.png" \
  -background "$BG" -gravity center -extent "${APPLE_PX}x${APPLE_PX}" \
  -alpha remove -alpha off -strip \
  "$tmp/out.png"

# Everything above writes to $tmp, so a convert that dies midway cannot leave a
# truncated icon in the working tree. Verify both renders are readable before
# replacing anything, so a corrupt-but-nonempty output is caught here rather
# than at commit time.
for staged in "$tmp/out.ico" "$tmp/out.png"; do
  [ -s "$staged" ] || { echo "ERROR: $staged missing or empty." >&2; exit 1; }
  identify "$staged" >/dev/null 2>&1 || {
    echo "ERROR: $staged is not a readable image." >&2
    exit 1
  }
done

# Each mv is an atomic rename (same filesystem, see $tmp above), so neither icon
# can be observed half-written. The pair is NOT transactional: if the second
# rename fails the tree holds one new and one old icon. That is acceptable for a
# dev-time generator whose outputs are git-tracked — `git status` shows it and
# re-running fixes it — but it is not a guarantee to rely on elsewhere.
mv "$tmp/out.ico" "$ICO"
mv "$tmp/out.png" "$APPLE"

# identify prints one line per ICO frame; join them so the summary is one line.
echo "$ICO: $(identify -format '%wx%h ' "$ICO")($(stat -c%s "$ICO") bytes)"
echo "$APPLE: $(identify -format '%wx%h ' "$APPLE")($(stat -c%s "$APPLE") bytes)"
