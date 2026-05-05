#!/usr/bin/env bash
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SCRIPT_SRC="$INSTALLER_DIR/statusline.sh"
SCRIPT_DST="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

if [ ! -f "$SCRIPT_SRC" ]; then
    echo "Error: statusline.sh not found at $SCRIPT_SRC" >&2
    exit 1
fi

if ! command -v node >/dev/null 2>&1; then
    echo "Error: node not in PATH. Install Node.js first." >&2
    exit 1
fi

mkdir -p "$CLAUDE_DIR"

# Copy script preserving LF endings
if command -v dos2unix >/dev/null 2>&1; then
    cp "$SCRIPT_SRC" "$SCRIPT_DST"
    dos2unix "$SCRIPT_DST" 2>/dev/null || true
else
    tr -d '\r' <"$SCRIPT_SRC" >"$SCRIPT_DST"
fi
chmod +x "$SCRIPT_DST"
echo "Installed: $SCRIPT_DST"

# Detect bash invocation for statusLine command
detect_bash_command() {
    local script_path="$1"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            local git_bash=""
            for candidate in \
                "/c/Program Files/Git/bin/bash.exe" \
                "/c/Program Files (x86)/Git/bin/bash.exe" \
                "$LOCALAPPDATA/Programs/Git/bin/bash.exe"; do
                if [ -f "$candidate" ]; then
                    git_bash="$candidate"
                    break
                fi
            done
            if [ -z "$git_bash" ]; then
                echo "Error: Git Bash not found." >&2
                exit 1
            fi
            local win_bash
            win_bash=$(cygpath -w "$git_bash")
            local win_script
            win_script=$(cygpath -w "$script_path")
            printf '"%s" "%s"' "$win_bash" "$win_script"
            ;;
        *)
            printf '%s' "$script_path"
            ;;
    esac
}

STATUSLINE_CMD=$(detect_bash_command "$SCRIPT_DST")

SETTINGS_PATH="$SETTINGS" STATUSLINE_CMD="$STATUSLINE_CMD" node -e '
const fs = require("fs");
const path = process.env.SETTINGS_PATH;
let cfg = {};
if (fs.existsSync(path)) {
    try { cfg = JSON.parse(fs.readFileSync(path, "utf8")); } catch (e) {
        console.error("Failed to parse existing settings.json: " + e.message);
        process.exit(1);
    }
}
cfg.env = cfg.env || {};
cfg.env.FORCE_HYPERLINK = "1";
cfg.statusLine = { type: "command", command: process.env.STATUSLINE_CMD };
fs.writeFileSync(path, JSON.stringify(cfg, null, 2) + "\n");
console.log("Patched: " + path);
'

echo
echo "Done. Restart Claude Code to load the new status line."
