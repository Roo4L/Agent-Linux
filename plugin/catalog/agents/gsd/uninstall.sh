#!/usr/bin/env bash
set -euo pipefail
# gsd uninstall.sh — Phase 4 SCAFFOLD; real body lands Phase 5.
#
# Phase 5 body will execute:
#   npm uninstall -g get-shit-done-cc   # no privilege escalation; runs as agent via dispatcher
# Idempotent: npm treats "uninstall missing" as exit 0 by default.

echo "gsd: SCAFFOLD — would run 'npm uninstall -g get-shit-done-cc' as agent in Phase 5"
exit 0
