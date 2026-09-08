#!/usr/bin/env bash

# -------------------------------------------------------------------------------- #
# Single script: failing command with stderr (ERR).                                #
# -------------------------------------------------------------------------------- #

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/src/trapper.sh"

ls /no/such/trapper/demo/path
