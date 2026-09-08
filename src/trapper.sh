#!/usr/bin/env bash

# -------------------------------------------------------------------------------- #
# Description                                                                      #
# -------------------------------------------------------------------------------- #
# Trapper is a sourceable Bash plugin for debugging scripts. It installs ERR and   #
# EXIT traps and, on failure, prints the filename, line number, error message,     #
# failing command, a short snippet, and the call stack.                            #
#                                                                                  #
# Must be sourced. Set TRAPPER_SET_STRICT=0 before sourcing to skip                #
# `set -Eeuo pipefail`. Colour follows NO_COLOR / FORCE_COLOR / TTY.               #
# -------------------------------------------------------------------------------- #

TRAPPER_VERSION="0.0.0"

get_version()
{
    printf '%s\n' "${TRAPPER_VERSION}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '%s\n' "trapper.sh must be sourced, not executed." >&2
    exit 2
fi

if [[ "${TRAPPER_SET_STRICT:-1}" != "0" ]]; then
    set -Eeuo pipefail
fi

# -------------------------------------------------------------------------------- #
# Colour (stdout). Never fail the host script if tput/TERM is unavailable.         #
# -------------------------------------------------------------------------------- #

_trapper_colour_enabled()
{
    local fd="$1"
    local ncolors

    if [[ -n "${NO_COLOR-}" ]]; then
        return 1
    fi
    case "${FORCE_COLOR-}" in
        1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]) return 0 ;;
        0|[Ff][Aa][Ll][Ss][Ee]|[Nn][Oo]) return 1 ;;
    esac
    [[ -t "${fd}" ]] || return 1
    ncolors="$(tput colors 2>/dev/null || true)"
    [[ -n "${ncolors}" && "${ncolors}" -ge 8 ]]
}

_trapper_init_colour()
{
    red=""
    reset=""
    bold=""
    if _trapper_colour_enabled 1; then
        red="$(tput setaf 1 2>/dev/null || true)"
        reset="$(tput sgr0 2>/dev/null || true)"
        bold="$(tput bold 2>/dev/null || true)"
        [[ -n "${red}" ]] || red=$'\033[31m'
        [[ -n "${reset}" ]] || reset=$'\033[0m'
        [[ -n "${bold}" ]] || bold=$'\033[1m'
    fi
}

_trapper_init_colour

# -------------------------------------------------------------------------------- #
# Capture stderr in a unique temp file. fd 8 holds the original stderr.            #
# -------------------------------------------------------------------------------- #

ERROR_FILE="$(mktemp "${TMPDIR:-/tmp}/trapper.XXXXXX")" || {
    printf '%s\n' "trapper: failed to create a temporary file." >&2
    return 1
}

exec 8>&2
exec 2>"${ERROR_FILE}"

_trapper_restore_stderr()
{
    exec 2>&8
    exec 8>&-
}

_trapper_read_errors()
{
    if [[ -f "${ERROR_FILE}" ]]; then
        cat "${ERROR_FILE}"
        rm -f "${ERROR_FILE}"
    fi
}

# -------------------------------------------------------------------------------- #
# Location, snippet, and stack helpers.                                            #
# -------------------------------------------------------------------------------- #

_trapper_parse_caller_frame()
{
    local frame="$1"
    _TRAPPER_FRAME_LINE=""
    _TRAPPER_FRAME_FILE=""
    if [[ "${frame}" =~ ^([0-9]+)[[:space:]]+([^[:space:]]+)[[:space:]]+(.*)$ ]]; then
        _TRAPPER_FRAME_LINE="${BASH_REMATCH[1]}"
        _TRAPPER_FRAME_FILE="${BASH_REMATCH[3]}"
    elif [[ "${frame}" =~ ^([0-9]+)[[:space:]]+(.*)$ ]]; then
        _TRAPPER_FRAME_LINE="${BASH_REMATCH[1]}"
        _TRAPPER_FRAME_FILE="${BASH_REMATCH[2]}"
    fi
}

_trapper_is_plugin_file()
{
    local file="$1"
    [[ "${file}" == *"/trapper.sh" || "${file}" == "trapper.sh" ]]
}

_trapper_locate()
{
    local i=0
    local frame

    _TRAPPER_LINE="${BASH_LINENO[0]:-}"
    _TRAPPER_FILE="${BASH_SOURCE[1]:-}"

    while frame="$(caller "${i}")"; do
        _trapper_parse_caller_frame "${frame}"
        if [[ -n "${_TRAPPER_FRAME_FILE}" ]] && ! _trapper_is_plugin_file "${_TRAPPER_FRAME_FILE}"; then
            _TRAPPER_LINE="${_TRAPPER_FRAME_LINE}"
            _TRAPPER_FILE="${_TRAPPER_FRAME_FILE}"
            return 0
        fi
        i=$((i + 1))
    done
}

_trapper_print_snippet()
{
    local file="$1"
    local line="$2"

    if [[ -z "${file}" || -z "${line}" || ! -f "${file}" ]]; then
        return 0
    fi
    awk 'NR>L-4 && NR<L+4 { printf "    %-5d%s%s%4s%s%s\n", NR, bold, red, (NR==L?">>> ":""), reset, $0 }' \
        L="${line}" bold="${bold}" red="${red}" reset="${reset}" "${file}"
}

_trapper_print_stack()
{
    local i=0
    local frame
    local printed=0

    while frame="$(caller "${i}")"; do
        _trapper_parse_caller_frame "${frame}"
        if [[ -n "${_TRAPPER_FRAME_FILE}" ]] && ! _trapper_is_plugin_file "${_TRAPPER_FRAME_FILE}"; then
            if [[ "${printed}" -eq 0 ]]; then
                printf '\n%s%sCall stack:%s\n' "${bold}" "${red}" "${reset}"
            fi
            printf '    %s\n' "${frame}"
            printed=1
        fi
        i=$((i + 1))
    done
}

_trapper_print_header()
{
    local file_disp="$1"
    local line="$2"
    local msg="$3"

    if [[ -n "${msg}" ]]; then
        printf '\n%s%sFailed in %s on line %s with the following error:\n%s%s\n' \
            "${bold}" "${red}" "${file_disp}" "${line}" "${msg}" "${reset}"
    elif [[ -n "${file_disp}" || -n "${line}" ]]; then
        printf '\n%s%sFailed in %s on line %s with no error message.%s\n' \
            "${bold}" "${red}" "${file_disp}" "${line}" "${reset}"
    else
        printf '\n%s%sFailed with no error message.%s\n' "${bold}" "${red}" "${reset}"
    fi
}

# -------------------------------------------------------------------------------- #
# Trap handler. Always exit with the original status so CI sees the failure.       #
# -------------------------------------------------------------------------------- #

failure()
{
    trap '' ERR EXIT

    local code="$1"
    local signal="$2"
    local regex="^(.*): line ([[:digit:]]+): (.*)"
    local errors_raw=""
    local error_msg=""
    local matched=0
    local line
    local parsed_file
    local file_disp
    local failing_cmd="${BASH_COMMAND:-}"

    if [[ "${code}" == "0" ]]; then
        if [[ -s "${ERROR_FILE}" ]]; then
            cat "${ERROR_FILE}" >&8
        fi
        rm -f "${ERROR_FILE}"
        _trapper_restore_stderr
        return 0
    fi

    _trapper_locate
    errors_raw="$(_trapper_read_errors)"
    _trapper_restore_stderr

    if [[ "${signal}" == "EXIT" ]]; then
        if [[ -n "${errors_raw}" ]]; then
            while IFS= read -r line || [[ -n "${line}" ]]; do
                if [[ "${line}" =~ ${regex} ]]; then
                    matched=1
                    parsed_file="${BASH_REMATCH[1]}"
                    _TRAPPER_LINE="${BASH_REMATCH[2]}"
                    error_msg="${BASH_REMATCH[3]}"
                    if [[ -f "${parsed_file}" ]]; then
                        _TRAPPER_FILE="${parsed_file}"
                    fi
                    file_disp="${_TRAPPER_FILE##*/}"
                    _trapper_print_header "${file_disp}" "${_TRAPPER_LINE}" "${error_msg}"
                fi
            done <<< "${errors_raw}"
            if [[ "${matched}" -eq 0 ]]; then
                file_disp="${_TRAPPER_FILE##*/}"
                _trapper_print_header "${file_disp}" "${_TRAPPER_LINE}" "${errors_raw}"
            fi
        else
            file_disp="${_TRAPPER_FILE##*/}"
            _trapper_print_header "${file_disp}" "${_TRAPPER_LINE}" ""
        fi
    elif [[ "${signal}" == "ERR" ]]; then
        file_disp="${_TRAPPER_FILE##*/}"
        _trapper_print_header "${file_disp}" "${_TRAPPER_LINE}" "${errors_raw}"
    else
        printf '\n%s%sUnhandled signal '\''%s'\''%s\n' "${bold}" "${red}" "${signal}" "${reset}"
    fi

    if [[ -n "${failing_cmd}" && "${failing_cmd}" != failure* ]]; then
        printf '%s%sCommand: %s%s\n' "${bold}" "${red}" "${failing_cmd}" "${reset}"
    fi

    _trapper_print_snippet "${_TRAPPER_FILE}" "${_TRAPPER_LINE}"
    _trapper_print_stack

    exit "${code}"
}

# -------------------------------------------------------------------------------- #
# Install traps. ${?} must expand when the trap fires, not when it is set.         #
# -------------------------------------------------------------------------------- #

trap_with_arg()
{
    local func="$1"
    shift
    local sig

    for sig; do
        # shellcheck disable=SC2064
        trap "${func} ${sig}" "${sig}"
    done
}

# shellcheck disable=SC2016
trap_with_arg 'failure ${?}' ERR EXIT
