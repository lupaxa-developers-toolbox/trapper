#!/usr/bin/env bash

# -------------------------------------------------------------------------------- #
# Single script: unbound variable (EXIT / nounset).                                #
# -------------------------------------------------------------------------------- #

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/src/trapper.sh"

# shellcheck disable=SC2154
echo "${FRED}"
