#!/usr/bin/env bash

# -------------------------------------------------------------------------------- #
# Middle script in an execute stack.                                               #
# -------------------------------------------------------------------------------- #

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/src/trapper.sh"

"$(dirname "${BASH_SOURCE[0]}")/child-2.sh"
