#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRAPPER="${ROOT}/src/trapper.sh"
FAILS=0
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

assert_eq() {
    local got="$1"
    local want="$2"
    local name="$3"
    if [[ "${got}" == "${want}" ]]; then
        printf 'PASS  %s\n' "${name}"
        return 0
    fi
    printf 'FAIL  %s\n' "${name}"
    printf '      got:  [%s]\n' "${got}"
    printf '      want: [%s]\n' "${want}"
    FAILS=$((FAILS + 1))
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local name="$3"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        printf 'PASS  %s\n' "${name}"
        return 0
    fi
    printf 'FAIL  %s\n' "${name}"
    printf '      missing: [%s]\n' "${needle}"
    printf '      output:\n%s\n' "${haystack}"
    FAILS=$((FAILS + 1))
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local name="$3"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        printf 'PASS  %s\n' "${name}"
        return 0
    fi
    printf 'FAIL  %s\n' "${name}"
    printf '      should not contain: [%s]\n' "${needle}"
    printf '      output:\n%s\n' "${haystack}"
    FAILS=$((FAILS + 1))
}

run_script() {
    local path="$1"
    set +e
    RUN_OUT="$(NO_COLOR=1 bash "${path}" 2>&1)"
    RUN_RC=$?
    set -e
}

# ---------------------------------------------------------------------------
# Must be sourced
# ---------------------------------------------------------------------------
set +e
EXEC_OUT="$(NO_COLOR=1 bash "${TRAPPER}" 2>&1)"
EXEC_RC=$?
set -e
assert_eq "${EXEC_RC}" "2" "executing trapper.sh exits 2"
assert_contains "${EXEC_OUT}" "must be sourced" "executing trapper.sh explains sourcing"

# ---------------------------------------------------------------------------
# Successful script: exit 0, stderr visible, no leftover /tmp/trapper
# ---------------------------------------------------------------------------
cat > "${WORKDIR}/ok.sh" <<EOF
#!/usr/bin/env bash
source "${TRAPPER}"
echo "warn-on-stderr" >&2
echo "ok-on-stdout"
EOF
chmod +x "${WORKDIR}/ok.sh"
rm -f /tmp/trapper
run_script "${WORKDIR}/ok.sh"
assert_eq "${RUN_RC}" "0" "successful script exits 0"
assert_contains "${RUN_OUT}" "warn-on-stderr" "successful script keeps stderr"
assert_contains "${RUN_OUT}" "ok-on-stdout" "successful script keeps stdout"
if [[ -e /tmp/trapper ]]; then
    printf 'FAIL  success does not leave /tmp/trapper\n'
    FAILS=$((FAILS + 1))
else
    printf 'PASS  success does not leave /tmp/trapper\n'
fi

# ---------------------------------------------------------------------------
# Unbound variable: non-zero exit, file, line, message, snippet
# ---------------------------------------------------------------------------
cat > "${WORKDIR}/unbound.sh" <<EOF
#!/usr/bin/env bash
source "${TRAPPER}"
echo "before-unbound"
echo "\${FRED}"
EOF
run_script "${WORKDIR}/unbound.sh"
assert_eq "$([[ "${RUN_RC}" -ne 0 ]] && echo yes || echo no)" "yes" "unbound variable exits non-zero"
assert_contains "${RUN_OUT}" "unbound.sh" "unbound report names the script"
assert_contains "${RUN_OUT}" "unbound variable" "unbound report includes the error"
assert_contains "${RUN_OUT}" ">>>" "unbound report includes a snippet marker"
assert_contains "${RUN_OUT}" "Call stack:" "unbound report includes a call stack"

# ---------------------------------------------------------------------------
# Command failure with percent signs in stderr (ERR path)
# ---------------------------------------------------------------------------
cat > "${WORKDIR}/percent.sh" <<EOF
#!/usr/bin/env bash
source "${TRAPPER}"
printf '%s\\n' '100% boom' >&2
false
EOF
run_script "${WORKDIR}/percent.sh"
assert_eq "$([[ "${RUN_RC}" -ne 0 ]] && echo yes || echo no)" "yes" "command failure exits non-zero"
assert_contains "${RUN_OUT}" "100% boom" "error text with percent is printed literally"
assert_contains "${RUN_OUT}" "percent.sh" "command failure names the script"
assert_contains "${RUN_OUT}" "Command:" "command failure shows BASH_COMMAND"

# ---------------------------------------------------------------------------
# Non-matching stderr still printed (ls of a missing path)
# ---------------------------------------------------------------------------
cat > "${WORKDIR}/missing.sh" <<EOF
#!/usr/bin/env bash
source "${TRAPPER}"
ls /no/such/trapper/demo/path
EOF
run_script "${WORKDIR}/missing.sh"
assert_eq "$([[ "${RUN_RC}" -ne 0 ]] && echo yes || echo no)" "yes" "missing-path failure exits non-zero"
assert_contains "${RUN_OUT}" "no/such/trapper/demo/path" "missing-path stderr is replayed"

# ---------------------------------------------------------------------------
# Source stack: only parent sources trapper
# ---------------------------------------------------------------------------
mkdir -p "${WORKDIR}/source-stack"
cat > "${WORKDIR}/source-stack/child.sh" <<'EOF'
#!/usr/bin/env bash
boom()
{
    ls /no/such/trapper/demo/path
}
boom
EOF
cat > "${WORKDIR}/source-stack/parent.sh" <<EOF
#!/usr/bin/env bash
source "${TRAPPER}"
source "${WORKDIR}/source-stack/child.sh"
EOF
run_script "${WORKDIR}/source-stack/parent.sh"
assert_eq "$([[ "${RUN_RC}" -ne 0 ]] && echo yes || echo no)" "yes" "source-stack exits non-zero"
assert_contains "${RUN_OUT}" "child.sh" "source-stack report names the sourced child"

# ---------------------------------------------------------------------------
# Execute stack: each executed script sources trapper
# ---------------------------------------------------------------------------
mkdir -p "${WORKDIR}/execute-stack"
cat > "${WORKDIR}/execute-stack/child.sh" <<EOF
#!/usr/bin/env bash
source "${TRAPPER}"
ls /no/such/trapper/demo/path
EOF
chmod +x "${WORKDIR}/execute-stack/child.sh"
cat > "${WORKDIR}/execute-stack/parent.sh" <<EOF
#!/usr/bin/env bash
source "${TRAPPER}"
"${WORKDIR}/execute-stack/child.sh"
EOF
run_script "${WORKDIR}/execute-stack/parent.sh"
assert_eq "$([[ "${RUN_RC}" -ne 0 ]] && echo yes || echo no)" "yes" "execute-stack exits non-zero"
assert_contains "${RUN_OUT}" "child.sh" "execute-stack report names the child script"

# ---------------------------------------------------------------------------
# Path with spaces: snippet still works
# ---------------------------------------------------------------------------
mkdir -p "${WORKDIR}/dir with spaces"
cat > "${WORKDIR}/dir with spaces/my script.sh" <<EOF
#!/usr/bin/env bash
source "${TRAPPER}"
ls /no/such/trapper/demo/path
EOF
run_script "${WORKDIR}/dir with spaces/my script.sh"
assert_eq "$([[ "${RUN_RC}" -ne 0 ]] && echo yes || echo no)" "yes" "spaced path exits non-zero"
assert_contains "${RUN_OUT}" "my script.sh" "spaced path report names the script"
assert_contains "${RUN_OUT}" ">>>" "spaced path still shows a snippet"

# ---------------------------------------------------------------------------
# TRAPPER_SET_STRICT=0 does not enable nounset
# ---------------------------------------------------------------------------
cat > "${WORKDIR}/loose.sh" <<EOF
#!/usr/bin/env bash
TRAPPER_SET_STRICT=0
source "${TRAPPER}"
printf '%s\\n' "\${FRED-ok-unset}"
EOF
run_script "${WORKDIR}/loose.sh"
assert_eq "${RUN_RC}" "0" "TRAPPER_SET_STRICT=0 leaves unset variables usable"

# ---------------------------------------------------------------------------
# NO_COLOR: no ANSI escapes
# ---------------------------------------------------------------------------
cat > "${WORKDIR}/nocolor.sh" <<EOF
#!/usr/bin/env bash
source "${TRAPPER}"
false
EOF
set +e
NOCOLOR_OUT="$(NO_COLOR=1 bash "${WORKDIR}/nocolor.sh" 2>&1)"
set -e
if [[ "${NOCOLOR_OUT}" == *$'\033['* ]]; then
    printf 'FAIL  NO_COLOR suppresses ANSI\n'
    FAILS=$((FAILS + 1))
else
    printf 'PASS  NO_COLOR suppresses ANSI\n'
fi

if [[ "${FAILS}" -ne 0 ]]; then
    printf '\n%d test(s) failed\n' "${FAILS}" >&2
    exit 1
fi

echo "PASS: test_trapper.sh"
