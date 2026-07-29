# shellcheck shell=bash
# lib/core/profiles.sh — profile → module membership (testable contract)
#
# RUN_PROFILE: quick | auto | deep | all
# For auto, optional env gates: ICLOUD_FIX_ENABLED, UNIVERSAL_UPDATES, etc.

# Quick profile whitelist (lean daily)
PROFILE_QUICK_MODULES="Healer|Homebrew|App Store|macOS System|Cleanup|Security Suite|Broken Symlinks|Sleep Blockers|Simulator Fix|Time Machine"

# Returns 0 if module $1 should run under current RUN_PROFILE
module_in_profile() {
    local name="$1"
    case "${RUN_PROFILE:-auto}" in
        quick)
            case "|$PROFILE_QUICK_MODULES|" in
                *"|$name|"*) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        deep|all)
            return 0
            ;;
        auto|*)
            case "$name" in
                "iCloud Fix")           [ "${ICLOUD_FIX_ENABLED:-false}" = "true" ] || return 1 ;;
                "Dev Updates")          [ "${UNIVERSAL_UPDATES:-false}" = "true" ] || return 1 ;;
                "Docs Order")           [ "${DOCS_ORDER_ENABLED:-true}" = "true" ] || return 1 ;;
                "Docker Prune")         [ "${CLEAN_DOCKER:-false}" = "true" ] || return 1 ;;
                "Dev Caches")           [ "${CLEAN_DEV_CACHES:-true}" = "true" ] || return 1 ;;
                "Git repos")            [ "${RUN_GIT_REPOS:-false}" = "true" ] || return 1 ;;
                "Sniffnet")             [ "${RUN_SNIFFNET:-false}" = "true" ] || return 1 ;;
                "Performance")          [ "${RUN_PERF_TUNE:-false}" = "true" ] || return 1 ;;
                "Benchmark")            return 1 ;;
                "node_modules"|".DS_Store") return 1 ;;
                "Brew Bottle Age"|"APFS Snapshots"|"Kext Audit"|"Receipts Audit"|"LaunchServices")
                    return 1 ;;
            esac
            return 0
            ;;
    esac
}

# List modules that would run (for contract tests / meister why profile)
# Args: profile name, then module names to check
profile_list_modules() {
    local save="${RUN_PROFILE:-auto}"
    RUN_PROFILE="$1"
    shift
    local m
    for m in "$@"; do
        if module_in_profile "$m"; then
            printf '%s\n' "$m"
        fi
    done
    RUN_PROFILE="$save"
}
