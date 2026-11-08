# shellcheck shell=bash
# scripts/release-lib.sh — source-tarball helpers for release.sh (issue #6).
# GitHub's archive URL can return 504 for minutes while codeload serves the
# identical tarball, and a half-finished release must be resumable.

# Prints the archive URL (the one the Formula uses) and the codeload fallback.
release_tarball_urls() {
    local repo="$1" version="$2"
    echo "https://github.com/$repo/archive/refs/tags/v${version}.tar.gz"
    echo "https://codeload.github.com/$repo/tar.gz/refs/tags/v${version}"
}

# release_fetch_tarball OUT URL... — tries every URL per round, backing off
# between rounds (RELEASE_RETRY_SLEEP seconds, doubling, capped at 30).
release_fetch_tarball() {
    local out="$1" round url pause="${RELEASE_RETRY_SLEEP:-2}"
    shift
    for ((round = 1; round <= ${RELEASE_FETCH_ROUNDS:-6}; round++)); do
        for url in "$@"; do
            rm -f "$out"
            if curl -fsSL --max-time 120 -o "$out" "$url" && [ -s "$out" ]; then
                return 0
            fi
            echo "Tarball not available from $url (round $round)" >&2
        done
        sleep "$pause"
        pause=$((pause * 2)); [ "$pause" -gt 30 ] && pause=30
    done
    rm -f "$out"
    return 1
}

# Prints new | resume | conflict for tag v<version> against <sha>.
release_existing_state() {
    local repo="$1" version="$2" sha="$3" tagged
    if ! gh release view "v${version}" -R "$repo" >/dev/null 2>&1; then
        echo new; return 0
    fi
    git fetch -q origin tag "v${version}" --no-tags 2>/dev/null || true
    tagged=$(git rev-parse "v${version}^{commit}" 2>/dev/null || true)
    if [ -n "$tagged" ] && [ "$tagged" = "$sha" ]; then echo resume; else echo conflict; fi
}

# Copies the verified tarball to the file name Homebrew uses for <url>, so the
# local install does not depend on the archive URL answering again.
release_seed_brew_cache() {
    local tarball="$1" url="$2" version="$3" dir hash
    dir="${HOMEBREW_CACHE:-$HOME/Library/Caches/Homebrew}/downloads"
    hash=$(printf %s "$url" | shasum -a 256 | awk '{print $1}')
    mkdir -p "$dir" && cp "$tarball" "$dir/${hash}--homebrew-meister-${version}.tar.gz"
}
