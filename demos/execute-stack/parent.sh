#!/usr/bin/env bash

# -------------------------------------------------------------------------------- #
# Parent executes children. Each executed script sources trapper.                  #
# -------------------------------------------------------------------------------- #

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/src/trapper.sh"

"$(dirname "${BASH_SOURCE[0]}")/child-1.sh"
