#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
overall=0
for t in test-*.sh; do
  echo "== $t =="
  bash "$t" || overall=1
done
if [[ $overall -eq 0 ]]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
  exit 1
fi
