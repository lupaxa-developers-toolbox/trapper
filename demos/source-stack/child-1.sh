#!/usr/bin/env bash

# -------------------------------------------------------------------------------- #
# Middle script in a source stack (does not source trapper).                       #
# -------------------------------------------------------------------------------- #

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/child-2.sh"
