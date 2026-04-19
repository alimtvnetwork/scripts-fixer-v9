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

# -- Helper: invoke git clone with stderr captured to a temp file ------------
invoke_git_clone() {
    local repo_url="$1"
    local target_path="$2"
    local err_file
    err_file="$(mktemp 2>/dev/null || echo "/tmp/scripts-fixer-git-err.$$")"

    echo "  [GIT] Cloning from : $repo_url"
    echo "  [GIT] Cloning into : $target_path"

    git clone --quiet "$repo_url" "$target_path" 2>"$err_file"
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "  [ERROR] git clone exit code: $exit_code"
        if [ -s "$err_file" ]; then
            echo "          Git stderr:"
            sed 's/^/            /' "$err_file"
        fi
    fi
    rm -f "$err_file" 2>/dev/null
    return $exit_code
}

# -- Helper: try to remove a folder, return 0 on success, 1 on failure -------
remove_folder_safe() {
    local path="$1"
    if [ ! -e "$path" ]; then
        return 0
    fi
    if rm -rf "$path" 2>/dev/null; then
        return 0
    fi
    echo "  [WARN] Could not remove $path"
    echo "         Reason: insufficient permissions or files in use."
    return 1
}

# -- Detect self-location (CWD is target OR contains 'scripts-fixer') --------
CWD="$(pwd)"
CWD_LEAF="$(basename "$CWD")"
IS_INSIDE_TARGET=0
HAS_SIBLING=0
if [ "$CWD_LEAF" = "scripts-fixer" ]; then IS_INSIDE_TARGET=1; fi
if [ -d "$CWD/scripts-fixer" ]; then HAS_SIBLING=1; fi

echo ""
echo "  [LOCATE] Current directory : $CWD"
echo "  [LOCATE] Target folder     : $FOLDER"
if [ "$IS_INSIDE_TARGET" = "1" ]; then
    echo "  [LOCATE] You are INSIDE a 'scripts-fixer' folder -- using relocation flow."
elif [ "$HAS_SIBLING" = "1" ]; then
    echo "  [LOCATE] A 'scripts-fixer' folder exists in CWD -- using relocation flow."
else
    echo "  [LOCATE] No conflict detected -- using direct clone flow."
fi

# -- Step out of folder if we're sitting inside it ---------------------------
if [ "$IS_INSIDE_TARGET" = "1" ]; then
    PARENT="$(dirname "$CWD")"
    echo "  [CD] Stepping out to parent  : $PARENT"
    cd "$PARENT" || {
        echo "  [ERROR] Could not cd to parent: $PARENT"
        exit 1
    }
fi

# -- Try to remove existing target folder ------------------------------------
REMOVED=1
if [ -e "$FOLDER" ]; then
    echo "  [CLEAN] Removing existing folder: $FOLDER"
    if remove_folder_safe "$FOLDER"; then
        echo "  [OK] Folder removed."
        REMOVED=1
    else
        echo "  [INFO] Direct removal failed -- will use TEMP staging fallback."
        REMOVED=0
    fi
fi

# -- Direct clone path (no conflict OR remove succeeded) ---------------------
if [ "$REMOVED" = "1" ]; then
    echo ""
    echo "  [>>] Direct clone into target..."
    if ! invoke_git_clone "$REPO" "$FOLDER"; then
        echo "          Repo   : $REPO"
        echo "          Target : $FOLDER"
        echo "          Verify the repo exists and your network is reachable."
        exit 1
    fi
    if [ ! -d "$FOLDER/.git" ]; then
        echo "  [ERROR] Clone finished but .git missing in: $FOLDER"
        exit 1
    fi
    echo "  [OK] Cloned successfully into $FOLDER"
else
    # -- TEMP staging fallback (remove failed -- folder is locked) -----------
    STAMP="$(date +%Y%m%d-%H%M%S)"
    TEMP_DIR="${TMPDIR:-/tmp}/scripts-fixer-bootstrap-$STAMP"
    echo ""
    echo "  [TEMP] Staging clone path  : $TEMP_DIR"
    if ! invoke_git_clone "$REPO" "$TEMP_DIR"; then
        echo "          Repo   : $REPO"
        echo "          Target : $TEMP_DIR"
        exit 1
    fi
    if [ ! -d "$TEMP_DIR/.git" ]; then
        echo "  [ERROR] Temp clone finished but .git missing in: $TEMP_DIR"
        exit 1
    fi
    echo "  [OK] Temp clone complete."

    # Copy contents over the locked folder (overwrite)
    echo "  [COPY] From : $TEMP_DIR"
    echo "  [COPY] To   : $FOLDER"
    if [ ! -d "$FOLDER" ]; then
        mkdir -p "$FOLDER" || {
            echo "  [ERROR] Could not create target folder: $FOLDER"
            exit 1
        }
    fi
    # cp -a preserves attrs; trailing /. copies contents (incl. dotfiles)
    CP_ERR="/tmp/scripts-fixer-cp-err.$$"
    if cp -a "$TEMP_DIR/." "$FOLDER/" 2>"$CP_ERR"; then
        echo "  [OK] Files copied into $FOLDER"
    else
        echo "  [ERROR] Copy from temp failed."
        echo "          Source : $TEMP_DIR"
        echo "          Target : $FOLDER"
        if [ -s "$CP_ERR" ]; then
            echo "          Reason :"
            sed 's/^/            /' "$CP_ERR"
        fi
        rm -f "$CP_ERR" 2>/dev/null
        echo "          Files remain in temp -- copy manually if needed: $TEMP_DIR"
        exit 1
    fi
    rm -f "$CP_ERR" 2>/dev/null

    # Best-effort cleanup of temp staging
    if remove_folder_safe "$TEMP_DIR"; then
        echo "  [CLEAN] Temp staging removed."
    else
        echo "  [WARN] Temp staging not removed: $TEMP_DIR"
    fi
fi

echo ""
echo "  [CD] Entering              : $FOLDER"
echo ""
echo "  Done! To get started:"
echo "    cd $FOLDER"
echo "    pwsh ./run.ps1 -d"
echo ""
