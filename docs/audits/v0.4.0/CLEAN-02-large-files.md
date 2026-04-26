# CLEAN-02 — Large file inventory

**Date:** 2026-04-26
**Status:** ✅ PASSED — repository is small and lean; no large binary cleanup required.

## Method

```bash
# Files >100 KB in current HEAD:
git ls-tree -r --long HEAD | awk '$4 != "-" && $4+0 > 100000 {printf "%10d %s\n", $4, $5}' | sort -rn

# All blobs >100 KB anywhere in history:
git rev-list --objects --all \
  | git cat-file --batch-check='%(objectname) %(objecttype) %(objectsize) %(rest)' \
  | awk '$2=="blob" && $3+0 > 100000 {printf "%10d %s\n", $3, $4}' | sort -rn -u

# All blobs >500 KB (the issue-AGE-6 ">1 MB" threshold relaxed for this small repo):
... | awk '… > 500000'

# Binary-shaped extensions in HEAD:
git ls-tree -r HEAD | awk '{print $4}' \
  | grep -iE '\.(png|jpg|jpeg|gif|pdf|zip|tar|gz|bz2|xz|7z|exe|dll|so|dylib|deb|rpm|qcow2|iso|woff|woff2|ttf|otf)$'

# Top-level dir totals:
for d in */; do echo -n "$d: "; git ls-tree -r --long HEAD "$d" | awk '$4 != "-" {sum += $4} END {printf "%.1f MB\n", sum/1024/1024}'; done
```

## Findings

### Files in current HEAD >100 KB

| Size (bytes) | Path |
|--------------|------|
| 113,833 | `.planning/phases/04-registry-cli-catalog-uninstall/04-RESEARCH.md` |

One 114 KB markdown file — the v0.3.0 Phase 4 research synthesis. Not a binary, not an artifact, not committed-by-mistake. Keep.

### Blobs anywhere in history >100 KB

| Size (bytes) | Path |
|--------------|------|
| 128,830 | `.planning/STATE.md` (snapshot at peak) |
| 123,113 | `.planning/STATE.md` (earlier snapshot) |
| 113,904 | `.planning/STATE.md` (earlier snapshot) |
| 113,833 | `.planning/phases/04-registry-cli-catalog-uninstall/04-RESEARCH.md` |
| 102,381 | `.planning/STATE.md` (earlier snapshot) |

All five are markdown narrative — historical snapshots of `STATE.md` (the GSD workflow rolling log) and the one Phase 4 research file. None are binary artifacts that need pruning.

### Blobs >500 KB anywhere in history

**0 entries.** Repository never contained a blob over half a megabyte at any point.

### Binary file types in HEAD

| Path | Kind | Notes |
|------|------|-------|
| `assets/crab-mascot.svg` | SVG | Brand asset, used by website. Keep. |
| `assets/favicon.svg` | SVG | Favicon, used by website. Keep. |
| `assets/og-image.svg` | SVG | OG/Twitter card image. Keep. (Per `.planning/PROJECT.md`'s known-issue note, may be converted to PNG for broader social platform support — separate website task, not v0.4.0 scope.) |

No PNG / JPEG / PDF / ZIP / archive / executable / shared-library / package-format / disk-image / font binaries in the tree.

### Top-level dir totals (HEAD)

| Dir | Size |
|-----|------|
| `agents/` | <0.1 MB |
| `assets/` | <0.1 MB |
| `docs/` | 0.4 MB |
| `packaging/` | <0.1 MB |
| `packer/` | <0.1 MB |
| `plugin/` | 0.2 MB |
| `scripts/` | <0.1 MB |
| `tests/` | 0.2 MB |
| **Total** | ~1.0 MB tracked content (excluding `.planning/` ~0.7 MB of GSD narrative) |

## Verdict

- **No files >500 KB anywhere in history.**
- **No binary artifacts** beyond 3 hand-written SVG brand files (each ~few KB).
- **No build outputs** committed (`.gitignore` covers `dist/`, `plugin/cli/dist/`, `tests/qemu/cache/`, `output/*.qcow2`, `node_modules/`, etc.).
- **No accidental commits** of release tarballs, packer images, deb packages, or test fixtures with payload data.

## Action: none

No file removal, history rewrite, or LFS migration required. CLEAN-02 closes GREEN.

## Pre-existing posture

The `check-added-large-files` hook in `.pre-commit-config.yaml` (default threshold: 500 KB) already prevents future regression. CLEAN-03 verifies this hook is still active.
