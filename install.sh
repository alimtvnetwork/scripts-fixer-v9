#!/usr/bin/env bash
# --------------------------------------------------------------------------
#  Scripts Fixer -- One-liner bootstrap installer (Unix/macOS)
#  Usage:  curl -fsSL https://raw.githubusercontent.com/alimtvnetwork/scripts-fixer-v7/main/install.sh | bash
#
#  Auto-discovery: probes scripts-fixer-vN repos (N = current+1..current+30)
#  in parallel and redirects to the newest published version.
#  Spec: spec/install-bootstrap/readme.md
#  Disable with: --no-upgrade  or  SCRIPTS_FIXER_NO_UPGRADE=1
#  Version check: --version (shows current and latest, no install)
# --------------------------------------------------------------------------
set -e

OWNER="alimtvnetwork"
BASE="scripts-fixer"
CURRENT=8   # <-- bump this when this file is copied into a new -vN repo
FOLDER="$HOME/scripts-fixer"
REPO="https://github.com/$OWNER/$BASE-v$CURRENT.git"

PROBE_MAX="${SCRIPTS_FIXER_PROBE_MAX:-30}"
if ! [[ "$PROBE_MAX" =~ ^[0-9]+$ ]] || [ "$PROBE_MAX" -lt 1 ] || [ "$PROBE_MAX" -gt 100 ]; then
    PROBE_MAX=30
fi

NO_UPGRADE=0
VERSION_MODE=0
for arg in "$@"; do
    case "$arg" in
        --no-upgrade) NO_UPGRADE=1 ;;
        --version) VERSION_MODE=1 ;;
    esac
done
if [ "${SCRIPTS_FIXER_NO_UPGRADE:-0}" = "1" ]; then NO_UPGRADE=1; fi

echo ""
echo "  Scripts Fixer -- Bootstrap Installer (v$CURRENT)"
echo ""

# -- Version check mode (discover + report, no clone) ----------------------
if [ "$VERSION_MODE" = "1" ]; then
    RANGE_END=$((CURRENT + PROBE_MAX))
    echo "  [VERSION] Bootstrap v$CURRENT"
    echo "  [SCAN] Probing v$((CURRENT + 1))..v$RANGE_END for newer releases (parallel)..."

    probe_one() {
        local n=$1
        local url="https://raw.githubusercontent.com/$OWNER/$BASE-v$n/main/install.sh"
        if curl -fsI -m 5 "$url" >/dev/null 2>&1; then
            echo "$n"
        fi
    }
    export -f probe_one
    export OWNER BASE

    LATEST=$(seq $((CURRENT + 1)) "$RANGE_END" \
        | xargs -P 20 -I{} bash -c 'probe_one "$@"' _ {} 2>/dev/null \
        | sort -n | tail -1)

    if [ -n "$LATEST" ] && [ "$LATEST" -gt "$CURRENT" ]; then
        echo "  [FOUND] Newer version available: v$LATEST"
        echo "  [RESOLVED] Would redirect to $BASE-v$LATEST"
    else
        echo "  [OK] You're on the latest (v$CURRENT)"
    fi
    echo ""
    echo "  (Use without --version flag to actually install)"
    exit 0
fi

# -- Auto-discovery: probe for newer -vN repos -------------------------------
if [ "${SCRIPTS_FIXER_REDIRECTED:-0}" = "1" ]; then
    echo "  [SKIP] Auto-discovery skipped (already redirected)."
elif [ "$NO_UPGRADE" = "1" ]; then
    echo "  [SKIP] Auto-discovery disabled."
elif ! command -v curl &>/dev/null; then
    echo "  [SKIP] curl unavailable -- skipping discovery."
else
    RANGE_END=$((CURRENT + PROBE_MAX))
    echo "  [SCAN] Currently on v$CURRENT. Probing v$((CURRENT + 1))..v$RANGE_END for newer releases (parallel)..."

    probe_one() {
        local n=$1
        local url="https://raw.githubusercontent.com/$OWNER/$BASE-v$n/main/install.sh"
        if curl -fsI -m 5 "$url" >/dev/null 2>&1; then
            echo "$n"
        fi
    }
    export -f probe_one
    export OWNER BASE

    LATEST=$(seq $((CURRENT + 1)) "$RANGE_END" \
        | xargs -P 20 -I{} bash -c 'probe_one "$@"' _ {} 2>/dev/null \
        | sort -n | tail -1)

    if [ -n "$LATEST" ] && [ "$LATEST" -gt "$CURRENT" ]; then
        echo "  [FOUND] Newer version available: v$LATEST"
        echo "  [REDIRECT] Switching to $BASE-v$LATEST..."
        echo ""
        export SCRIPTS_FIXER_REDIRECTED=1
        NEW_URL="https://raw.githubusercontent.com/$OWNER/$BASE-v$LATEST/main/install.sh"
        if curl -fsSL "$NEW_URL" | bash; then
            exit 0
        else
            echo "  [WARN] Failed to run v$LATEST installer -- falling back to v$CURRENT"
        fi
    else
        echo "  [OK] You're on the latest (v$CURRENT). Continuing..."
    fi
    echo ""
fi

# -- Check git is available ---------------------------------------------------
if ! command -v git &>/dev/null; then
    echo "  [ERROR] git is not installed. Install Git first, then re-run."
    echo "          https://git-scm.com/downloads"
    exit 1
fi

# -- Always wipe & re-clone (guarantees a clean, up-to-date checkout) --------
if [ -e "$FOLDER" ]; then
    echo "  [CLEAN] Existing folder found at $FOLDER -- removing for fresh clone..."
    if ! rm -rf "$FOLDER" 2>/dev/null; then
        echo "  [ERROR] Failed to remove existing folder: $FOLDER"
        echo "          Reason: insufficient permissions or files in use."
        echo "          Try: sudo rm -rf \"$FOLDER\"  then re-run."
        exit 1
    fi
    echo "  [OK] Removed previous folder."
fi

echo "  [>>] Cloning fresh into $FOLDER ..."
git clone "$REPO" "$FOLDER" >/dev/null 2>&1
CLONE_EXIT=$?

if [ $CLONE_EXIT -ne 0 ]; then
    echo "  [ERROR] Clone failed (exit $CLONE_EXIT) for repo: $REPO"
    echo "          Target folder: $FOLDER"
    echo "          Check your network and that the repo is public, then try again."
    exit 1
fi

if [ ! -d "$FOLDER/.git" ]; then
    echo "  [ERROR] Clone finished but .git missing in: $FOLDER"
    exit 1
fi
echo "  [OK] Cloned successfully."

echo ""
echo "  Done! To get started:"
echo "    cd $FOLDER"
echo "    pwsh ./run.ps1 -d"
echo ""
