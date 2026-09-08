#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash tests/test_version.sh
bash tests/test_trapper.sh
echo "PASS: all trapper tests"
