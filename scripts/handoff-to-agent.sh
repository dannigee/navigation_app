#!/bin/bash
# Repo-local CLI handoff launcher.
#
# Usage:
#   bash scripts/handoff-to-agent.sh <claude|codex|gemini|kimi|qwen|qwen-3.8|fable|ornith|gemma-26|grok> <SESSION_ID>
#
# Prompt lookup:
#   1. HANDOFF_FILE, if set
#   2. /tmp/{target}_handoff_{SESSION_ID}.md
#   3. /tmp/codex_handoff_{SESSION_ID}.md
#   4. /tmp/claude_handoff_{SESSION_ID}.md
#   5. /tmp/gemini_handoff_{SESSION_ID}.md
#
# Optional cwd state:
#   /tmp/ai_secretary_context_pct_{SESSION_ID}
#
# Test without launching a terminal:
#   HANDOFF_DRY_RUN=1 HANDOFF_FILE=/tmp/prompt.md bash scripts/handoff-to-kimi.sh my_session

set -euo pipefail

TARGET="${1:-}"
SESSION_ID="${2:-}"

if [ -z "$TARGET" ] || [ -z "$SESSION_ID" ]; then
    echo "ERROR: Usage: bash scripts/handoff-to-agent.sh <claude|codex|gemini|kimi|qwen|qwen-3.8|fable|ornith|gemma-26|grok> <SESSION_ID>" >&2
    exit 1
fi

case "$TARGET" in
    claude|codex|gemini|qwen|qwen-3.8|qwen38|fable|ornith|gemma-26|grok|kimi) ;;
    *)
        echo "ERROR: Unsupported target '$TARGET' (expected claude, codex, gemini, kimi, qwen, qwen-3.8, fable, ornith, gemma-26, or grok)" >&2
        exit 1
        ;;
esac

SESSION_ID=$(printf "%s" "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')
if [ -z "$SESSION_ID" ]; then
    echo "ERROR: Invalid SESSION_ID (empty after sanitization)" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="${HANDOFF_PROJECT_PATH:-}"
if [ -z "$PROJECT_PATH" ]; then
    PROJECT_PATH="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/.." && pwd))"
fi

STATE_FILE="/tmp/ai_secretary_context_pct_${SESSION_ID}"
WORK_DIR="$PROJECT_PATH"

find_python() {
    command -v python3 2>/dev/null || command -v python 2>/dev/null || true
}

if [ -z "${HANDOFF_WORK_DIR:-}" ] && [ -f "$STATE_FILE" ]; then
    PYTHON="$(find_python)"
    if [ -n "$PYTHON" ]; then
        STATE_CWD=$("$PYTHON" -c "import json,sys; print(json.load(open(sys.argv[1])).get('cwd',''))" "$STATE_FILE" 2>/dev/null || true)
        if [ -n "$STATE_CWD" ] && [ -d "$STATE_CWD" ]; then
            WORK_DIR="$STATE_CWD"
        fi
    fi
fi
if [ -n "${HANDOFF_WORK_DIR:-}" ]; then
    WORK_DIR="$HANDOFF_WORK_DIR"
fi

# Pre-trust the workspace for the kimi target. kimi-code's trust gate is a
# JSON marker at ~/.kimi-code/workspace-trust/wd_<basename>_<sha256(realpath)[:12]>
# containing {"root": <realpath>, "trustedAt": <epoch ms>} (file schema and id
# algorithm verified against five live workspaces 2026-08-07). Without it the
# CLI stops at "trust this folder?" and the expect seed never reaches the input
# loop — the spawned session then sits idle forever.
if [ "$TARGET" = "kimi" ]; then
    KIMI_WS_ROOT=$(cd "$WORK_DIR" && pwd -P)
    KIMI_WS_ID="wd_$(basename "$KIMI_WS_ROOT")_$(printf '%s' "$KIMI_WS_ROOT" | shasum -a 256 | cut -c1-12)"
    KIMI_TRUST_FILE="$HOME/.kimi-code/workspace-trust/$KIMI_WS_ID"
    if [ ! -f "$KIMI_TRUST_FILE" ]; then
        mkdir -p "$HOME/.kimi-code/workspace-trust"
        printf '%s' "{\"root\":\"$KIMI_WS_ROOT\",\"trustedAt\":$(($(date +%s) * 1000))}" > "$KIMI_TRUST_FILE"
    fi
fi

# Auto-trust the workspace directory for the gemini (Antigravity CLI) target
if [ "$TARGET" = "gemini" ]; then
    PYTHON="$(find_python)"
    if [ -n "$PYTHON" ]; then
        "$PYTHON" -c '
import json
import os
import sys

settings_path = os.path.expanduser("~/.gemini/antigravity-cli/settings.json")
work_dir = os.path.abspath(sys.argv[1])

if os.path.exists(settings_path):
    try:
        with open(settings_path, "r") as f:
            data = json.load(f)
    except Exception:
        data = {}
else:
    data = {}

trusted = data.get("trustedWorkspaces", [])
if not isinstance(trusted, list):
    trusted = []

norm_work_dir = os.path.normpath(work_dir)
norm_trusted = [os.path.normpath(p) for p in trusted]

if norm_work_dir not in norm_trusted:
    trusted.append(work_dir)
    data["trustedWorkspaces"] = trusted
    try:
        os.makedirs(os.path.dirname(settings_path), exist_ok=True)
        with open(settings_path, "w") as f:
            json.dump(data, f, indent=2)
    except Exception:
        pass
' "$WORK_DIR" || true
    fi
fi

EXPLICIT_HANDOFF_FILE="${HANDOFF_FILE:-}"
HANDOFF_FILE=""
if [ -n "$EXPLICIT_HANDOFF_FILE" ]; then
    HANDOFF_FILE="$EXPLICIT_HANDOFF_FILE"
else
    for candidate in \
        "/tmp/${TARGET}_handoff_${SESSION_ID}.md" \
        "/tmp/codex_handoff_${SESSION_ID}.md" \
        "/tmp/claude_handoff_${SESSION_ID}.md" \
        "/tmp/gemini_handoff_${SESSION_ID}.md"; do
        if [ -f "$candidate" ]; then
            HANDOFF_FILE="$candidate"
            break
        fi
    done
fi

if [ -z "$HANDOFF_FILE" ] || [ ! -f "$HANDOFF_FILE" ]; then
    echo "ERROR: Handoff file not found for session '$SESSION_ID'." >&2
    echo "Looked for /tmp/${TARGET}_handoff_${SESSION_ID}.md, /tmp/codex_handoff_${SESSION_ID}.md, /tmp/claude_handoff_${SESSION_ID}.md, /tmp/gemini_handoff_${SESSION_ID}.md" >&2
    echo "Or set HANDOFF_FILE=/path/to/file.md." >&2
    exit 1
fi

HANDOFF_SIZE=$(wc -c < "$HANDOFF_FILE" | tr -d ' ')
if [ "$HANDOFF_SIZE" -lt 50 ]; then
    echo "ERROR: Handoff file too small (${HANDOFF_SIZE} bytes). Looks incomplete." >&2
    exit 1
fi

find_bin() {
    local name="$1"
    local env_name
    local env_value
    env_name="$(printf "%s" "$name" | tr '[:lower:]' '[:upper:]')_BIN"
    env_value="${!env_name:-}"

    if [ -n "$env_value" ] && [ -x "$env_value" ]; then
        echo "$env_value"
        return 0
    fi

    local found
    found=$(command -v "$name" 2>/dev/null || true)
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi

    local home
    home="${HOME:-/Users/danielgreig}"
    local candidate
    for candidate in \
        "/usr/local/bin/$name" \
        "/opt/homebrew/bin/$name" \
        "$home/.bun/bin/$name" \
        "$home/.local/bin/$name" \
        "$home/.npm-global/bin/$name" \
        "$home/.kimi-code/bin/$name" \
        "$home/.grok/bin/$name"; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    for candidate in "$home"/.nvm/versions/node/*/bin/"$name"; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

# qwen, qwen-3.8, fable, ornith, and gemma-26 all run through the local `claude` binary
# (pointed at a local model backend via env vars in the wrapper below).
if [ "$TARGET" = "qwen" ] || [ "$TARGET" = "qwen-3.8" ] || [ "$TARGET" = "qwen38" ] || [ "$TARGET" = "fable" ] || [ "$TARGET" = "ornith" ] || [ "$TARGET" = "gemma-26" ]; then
    TARGET_BIN=$(find_bin "claude" || true)
elif [ "$TARGET" = "gemini" ]; then
    # The npm `gemini` CLI is DEPRECATED for handoffs (Daniel, 2026-07-05).
    # The gemini/agy target runs Google's Antigravity CLI, which takes the
    # Claude-Code-style flags below. Resolution: GEMINI_BIN override, then
    # `agy`, then `antigravity` -- NEVER the deprecated `gemini` binary.
    if [ -n "${GEMINI_BIN:-}" ] && [ -x "${GEMINI_BIN}" ]; then
        TARGET_BIN="$GEMINI_BIN"
    else
        TARGET_BIN=$(find_bin "agy" || find_bin "antigravity" || true)
    fi
elif [ "$TARGET" = "kimi" ]; then
    # kimi-code (Node, ~/.kimi-code/bin/kimi) is the current CLI. Its bin dir
    # is only on PATH in interactive shells, so check it EXPLICITLY first
    # (deterministic, PATH-independent — the same trap the daniel-ai-secretary
    # launcher documents). KIMI_BIN overrides. Never resolve kimi-cli (the
    # legacy Python CLI) for this target.
    if [ -n "${KIMI_BIN:-}" ] && [ -x "${KIMI_BIN}" ]; then
        TARGET_BIN="$KIMI_BIN"
    elif [ -x "$HOME/.kimi-code/bin/kimi" ]; then
        TARGET_BIN="$HOME/.kimi-code/bin/kimi"
    else
        TARGET_BIN=$(find_bin "kimi" || true)
    fi
else
    TARGET_BIN=$(find_bin "$TARGET" || true)
fi

if [ -z "$TARGET_BIN" ]; then
    case "$TARGET" in
        gemini) echo "ERROR: 'agy' or 'antigravity' not found. Install it or set GEMINI_BIN=/path/to/agy." >&2 ;;
        qwen) echo "ERROR: 'claude' not found; qwen handoff uses Claude Code against local Qwen via Ollama." >&2 ;;
        qwen-3.8|qwen38) echo "ERROR: 'claude' not found; qwen-3.8 handoff uses Claude Code against local Qwen 3.8 MLX bridge (:8777)." >&2 ;;
        fable) echo "ERROR: 'claude' not found; fable handoff launches Claude Code pinned to Fable." >&2 ;;
        ornith) echo "ERROR: 'claude' not found; ornith handoff runs Claude Code against the local Ornith 1.0 35B MLX server (:8771)." >&2 ;;
        gemma-26) echo "ERROR: 'claude' not found; gemma-26 handoff runs Claude Code against the local Gemma 4 26B MLX bridge (:8775)." >&2 ;;
        *) echo "ERROR: '$TARGET' not found. Install it or set $(printf "%s" "$TARGET" | tr '[:lower:]' '[:upper:]')_BIN=/path/to/$TARGET." >&2 ;;
    esac
    exit 1
fi

quote_arg() {
    printf "%q" "$1"
}

# --- Automatic window tinting (Daniel, 2026-07-05; group key 2026-07-18) ------
# Purpose: make it easy to SEE which Terminal windows belong together.
# The invoking (main) session is tinted first, then each spawned handoff
# window is tinted to match.
#
# Color key (first match wins) — NOT unique per agent session id:
#   1. HANDOFF_TINT="r,g,b" (0-65535 each) forces an exact color
#   2. HANDOFF_TINT=off disables tinting
#   3. HANDOFF_GROUP=... explicit batch/lane label (recommended when one
#      worktree runs multiple independent batches)
#   4. WORK_DIR (lane worktree path) — default: Codex + Kimi + AGY reviews
#      for the same worktree share one tint
#   5. SESSION_ID last-resort fallback only
#
# Old behavior keyed only on SESSION_ID, so multi-reviewer launches
# (…_codex vs …_agy) got DIFFERENT colors and the main window was re-tinted
# on each spawn — defeating the visual-grouping purpose.
# tmux path is untinted (no per-window bg). Default Terminal.app background
# is NOT a tint — never "match" it.

tint_color_for_session() {
    if [ "${HANDOFF_TINT:-}" = "off" ]; then
        return 1
    fi
    if [ -n "${HANDOFF_TINT:-}" ]; then
        printf "%s" "$HANDOFF_TINT" | tr -d ' '
        return 0
    fi
    local palette=(
        "20000,4000,5000"    # dark red
        "3000,16000,8000"    # dark green
        "4000,8000,24000"    # dark blue
        "14000,5000,22000"   # dark purple
        "3000,15000,16000"   # dark teal
        "20000,10000,2000"   # dark amber
        "20000,4000,16000"   # dark magenta
        "12000,13000,3000"   # dark olive
    )
    local tint_key idx
    if [ -n "${HANDOFF_GROUP:-}" ]; then
        tint_key="$HANDOFF_GROUP"
    elif [ -n "${WORK_DIR:-}" ]; then
        tint_key="$WORK_DIR"
    else
        tint_key="$SESSION_ID"
    fi
    idx=$(printf "%s" "$tint_key" | cksum | awk '{print $1 % 8}')
    printf "%s" "${palette[$idx]}"
}

invoking_tty() {
    # Walk up the process tree to the nearest ancestor with a real tty --
    # the interactive session (e.g. a Claude Code window) that dispatched
    # this handoff. Sandboxed tool shells have no tty of their own.
    local pid=$$ t
    local _i
    for _i in 1 2 3 4 5 6 7 8; do
        t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
        if [ -n "$t" ] && [ "$t" != "??" ]; then
            printf "/dev/%s" "$t"
            return 0
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        if [ -z "$pid" ] || [ "$pid" = "0" ] || [ "$pid" = "1" ]; then
            return 1
        fi
    done
    return 1
}

tint_main_window() {
    # $1 = "r,g,b". Finds the dispatching session's Terminal tab by tty and
    # tints it. Silently a no-op when headless or not Terminal.app.
    local color="$1" tty_path r g b
    command -v osascript >/dev/null 2>&1 || return 0
    tty_path=$(invoking_tty) || return 0
    IFS=',' read -r r g b <<< "$color"
    osascript - "$tty_path" "$r" "$g" "$b" <<'TINTEOF' >/dev/null 2>&1 || true
on run argv
    set ttyPath to item 1 of argv
    set r to (item 2 of argv) as integer
    set g to (item 3 of argv) as integer
    set b to (item 4 of argv) as integer
    tell application "Terminal"
        repeat with w in windows
            repeat with t in tabs of w
                if tty of t is ttyPath then
                    set background color of t to {r, g, b}
                    return
                end if
            end repeat
        end repeat
    end tell
end run
TINTEOF
}

launch_description() {
    case "$TARGET" in
        claude) echo "$TARGET_BIN ${CLAUDE_MODEL:+--model $CLAUDE_MODEL }${CLAUDE_EFFORT:+--effort $CLAUDE_EFFORT }--dangerously-skip-permissions <PROMPT>" ;;
        codex) echo "$TARGET_BIN --yolo -C $WORK_DIR ${CODEX_MODEL:+--model $CODEX_MODEL }${CODEX_EFFORT:+-c model_reasoning_effort=$CODEX_EFFORT }<PROMPT>" ;;
        gemini) echo "$TARGET_BIN --dangerously-skip-permissions ${GEMINI_MODEL:+--model $GEMINI_MODEL }-i <PROMPT> (Antigravity CLI)" ;;
        kimi) echo "expect bracketed-paste seed into $TARGET_BIN --yolo (interactive; cwd=WORK_DIR=$WORK_DIR)" ;;
        qwen) echo "claude via Ollama model ${QWEN_MODEL:-qwen3.6:35b-a3b-coding-nvfp4} <PROMPT>" ;;
        qwen-3.8|qwen38) echo "zsh -lic 'claude-qwen-3.8 <PROMPT>' (delegates to the zsh function; it owns model, bridge, and guardian config)" ;;
        fable) echo "claude --model ${FABLE_MODEL:-claude-fable-5} <PROMPT>" ;;
        ornith) echo "claude -> Ornith 35B MLX (${ORNITH_BASE_URL:-http://localhost:8771}), --tools=\"\" <PROMPT>" ;;
        gemma-26) echo "claude -> Gemma 4 26B MLX bridge (${GEMMA_BASE_URL:-http://localhost:8775}) <PROMPT>" ;;
        # --yolo = always-approve (same as --always-approve / --permission-mode bypassPermissions).
        # Deny rules + PreToolUse hooks still apply. GROK_MODEL/GROK_EFFORT -> --model/--effort.
        grok) echo "$TARGET_BIN --yolo --model ${GROK_MODEL:-grok-4.6} --effort ${GROK_EFFORT:-high} --cwd $WORK_DIR <PROMPT>" ;;
    esac
}

if [ "${HANDOFF_DRY_RUN:-0}" = "1" ]; then
    echo "TARGET=$TARGET"
    echo "SESSION_ID=$SESSION_ID"
    echo "PROJECT_PATH=$PROJECT_PATH"
    echo "WORK_DIR=$WORK_DIR"
    echo "HANDOFF_FILE=$HANDOFF_FILE"
    echo "TARGET_BIN=$TARGET_BIN"
    echo "LAUNCH=$(launch_description)"
    exit 0
fi

WORK_DIR_Q=$(quote_arg "$WORK_DIR")
HANDOFF_FILE_Q=$(quote_arg "$HANDOFF_FILE")
TARGET_BIN_Q=$(quote_arg "$TARGET_BIN")
TARGET_Q=$(quote_arg "$TARGET")
QWEN_MODEL_Q=$(quote_arg "${QWEN_MODEL:-qwen3.6:35b-a3b-coding-nvfp4}")
# No QWEN38_* plumbing here on purpose: the qwen-3.8 target delegates to the
# claude-qwen-3.8 zsh function, which owns the model id, bridge URL, and
# guardian thresholds. Re-adding defaults here would imply this script is
# authoritative for them, which is how it drifted the first time.
FABLE_MODEL_Q=$(quote_arg "${FABLE_MODEL:-claude-fable-5}")
CLAUDE_MODEL_Q=$(quote_arg "${CLAUDE_MODEL:-}")
CLAUDE_EFFORT_Q=$(quote_arg "${CLAUDE_EFFORT:-}")
CODEX_MODEL_Q=$(quote_arg "${CODEX_MODEL:-}")
CODEX_EFFORT_Q=$(quote_arg "${CODEX_EFFORT:-}")
ORNITH_MODEL_Q=$(quote_arg "${ORNITH_MODEL:-leonsarmiento/Ornith-1.0-35B-4bit-mlx}")
ORNITH_BASE_URL_Q=$(quote_arg "${ORNITH_BASE_URL:-http://localhost:8771}")
GEMMA_MODEL_Q=$(quote_arg "${GEMMA_MODEL:-mlx-community/gemma-4-26b-a4b-it-4bit}")
GEMMA_BASE_URL_Q=$(quote_arg "${GEMMA_BASE_URL:-http://localhost:8775}")
# Pinned rather than left to the grok CLI's own default. `~/.grok/config.toml`
# and mid-session /model + /effort picks PERSIST, so an unpinned dispatch silently
# inherits whatever was last clicked -- on 2026-08-19 three dispatches ran grok-4.5
# after a mid-flight model change, with nothing in the launcher to show it. Pinning
# here also puts model and effort in argv, which is what review dispositions verify
# against via `ps`. Override per-dispatch: GROK_EFFORT=xhigh when the grind is worth it.
GROK_MODEL_Q=$(quote_arg "${GROK_MODEL:-grok-4.6}")
GROK_EFFORT_Q=$(quote_arg "${GROK_EFFORT:-high}")
GEMINI_MODEL_Q=$(quote_arg "${GEMINI_MODEL:-}")
KIMI_SEED_EXP_Q=$(quote_arg "$SCRIPT_DIR/kimi-interactive-seed.exp")

WRAPPER=$(mktemp "/tmp/${TARGET}_handoff_launcher_XXXXXX")
chmod 700 "$WRAPPER"

cat > "$WRAPPER" <<WRAPPEREOF
#!/bin/bash
set -euo pipefail

cd $WORK_DIR_Q || exit 1

TARGET=$TARGET_Q
TARGET_BIN=$TARGET_BIN_Q
HANDOFF_FILE=$HANDOFF_FILE_Q
QWEN_MODEL=$QWEN_MODEL_Q
FABLE_MODEL=$FABLE_MODEL_Q
CLAUDE_MODEL=$CLAUDE_MODEL_Q
CLAUDE_EFFORT=$CLAUDE_EFFORT_Q
CODEX_MODEL=$CODEX_MODEL_Q
CODEX_EFFORT=$CODEX_EFFORT_Q
ORNITH_MODEL=$ORNITH_MODEL_Q
ORNITH_BASE_URL=$ORNITH_BASE_URL_Q
GEMMA_MODEL=$GEMMA_MODEL_Q
GEMMA_BASE_URL=$GEMMA_BASE_URL_Q
GROK_MODEL=$GROK_MODEL_Q
GROK_EFFORT=$GROK_EFFORT_Q
GEMINI_MODEL=$GEMINI_MODEL_Q
KIMI_SEED_EXP=$KIMI_SEED_EXP_Q

printf '\\033]0;%s\\007' "Handoff \$TARGET | $SESSION_ID"
echo "=== CLI handoff: launching \$TARGET ==="
echo "=== Working directory: $WORK_DIR ==="
echo "=== Handoff file: $HANDOFF_FILE ==="
echo ""

PROMPT=\$(cat "\$HANDOFF_FILE")
PROMPT_SIZE=\${#PROMPT}
if [ "\$PROMPT_SIZE" -gt 100000 ]; then
  PROMPT="\${PROMPT:0:80000}

[TRUNCATED - full handoff context at: $HANDOFF_FILE]
Read the full file from disk to get complete context."
fi

case "\$TARGET" in
  claude)
    CLAUDE_ARGS=()
    if [ -n "\$CLAUDE_MODEL" ]; then CLAUDE_ARGS+=(--model "\$CLAUDE_MODEL"); fi
    if [ -n "\$CLAUDE_EFFORT" ]; then CLAUDE_ARGS+=(--effort "\$CLAUDE_EFFORT"); fi
    exec "\$TARGET_BIN" "\${CLAUDE_ARGS[@]}" --dangerously-skip-permissions "\$PROMPT"
    ;;
  codex)
    CODEX_ARGS=(--yolo -C "$WORK_DIR")
    if [ -n "\$CODEX_MODEL" ]; then CODEX_ARGS+=(--model "\$CODEX_MODEL"); fi
    if [ -n "\$CODEX_EFFORT" ]; then CODEX_ARGS+=(-c "model_reasoning_effort=\$CODEX_EFFORT"); fi
    exec "\$TARGET_BIN" "\${CODEX_ARGS[@]}" "\$PROMPT"
    ;;
  gemini)
    # TARGET_BIN is the Antigravity CLI (agy), which takes these
    # Claude-Code-style flags. The deprecated npm gemini CLI (which wants
    # --approval-mode yolo instead) is never resolved for this target.
    # NOTE: never put backticks inside this heredoc — it is expanded, so
    # backticks EXECUTE (a backticked word here ran the npm gemini CLI on
    # every dispatch and hung a launch on 2026-07-06).
    # Optional GEMINI_MODEL -> --model (the GROK_MODEL pattern). If-guarded,
    # no arrays: bash 3.2 + set -u trips on empty-array expansion (LEARNED).
    if [ -n "\$GEMINI_MODEL" ]; then
      exec "\$TARGET_BIN" --dangerously-skip-permissions --model "\$GEMINI_MODEL" -i "\$PROMPT"
    fi
    exec "\$TARGET_BIN" --dangerously-skip-permissions -i "\$PROMPT"
    ;;
  kimi)
    # Persistent INTERACTIVE session, never print mode: spawn the CLI bare
    # (--yolo) and inject the handoff as a bracketed paste via
    # scripts/kimi-interactive-seed.exp, which leaves the session interactive
    # for the user. kimi --prompt is one-shot print mode; do not reintroduce
    # it. (NO backticks inside this heredoc — it is expanded, so they EXECUTE.)
    # cwd is the cd at the top of this wrapper; WORK_DIR honors
    # HANDOFF_WORK_DIR, so the handoff lands in the requested checkout.
    exec env KIMI_CLI_NO_AUTO_UPDATE=1 KIMI_BIN_PATH="\$TARGET_BIN" KIMI_SEED_PROMPT="\$PROMPT" /usr/bin/expect -f "\$KIMI_SEED_EXP"
    ;;
  qwen)
    exec env ANTHROPIC_BASE_URL=http://localhost:11434 ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_API_KEY='' ANTHROPIC_MODEL="\$QWEN_MODEL" ANTHROPIC_DEFAULT_OPUS_MODEL="\$QWEN_MODEL" ANTHROPIC_DEFAULT_SONNET_MODEL="\$QWEN_MODEL" ANTHROPIC_DEFAULT_HAIKU_MODEL="\$QWEN_MODEL" CLAUDE_CODE_SUBAGENT_MODEL="\$QWEN_MODEL" CLAUDE_CODE_DISABLE_1M_CONTEXT=1 CLAUDE_CODE_ATTRIBUTION_HEADER=0 DISABLE_TELEMETRY=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 "\$TARGET_BIN" "\$PROMPT"
    ;;
  qwen-3.8|qwen38)
    # Delegate to the claude-qwen-3.8 zsh function. It is the single source of
    # truth for the model id, bridge URL, guardian thresholds, context window,
    # launch-cwd header, working brief, and MCP config. It also validates the
    # running bridge's guardian config against an expected profile and refuses
    # to launch on mismatch, which this script cannot do on its own.
    #
    # Do NOT reimplement the env block here. It was inlined once and drifted: a
    # hardcoded CLAUDE_CODE_MAX_CONTEXT_TOKENS=100000 survived the 2026-08-18
    # retune to 30000, leaving a 100k client window against a guardian that
    # hard-stops at 22k — the exact mismatch that ends a session in a 502
    # instead of a clean handoff.
    #
    # Mirrors the canonical launcher:
    #   daniel-ai-secretary/scripts/handoff-to-agent.sh  (case qwen38)
    exec zsh -lic 'claude-qwen-3.8 "\$1"' -- "\$PROMPT"
    ;;
  fable)
    exec "\$TARGET_BIN" --model "\$FABLE_MODEL" --dangerously-skip-permissions "\$PROMPT"
    ;;
  ornith)
    if ! curl -sf --max-time 2 "\$ORNITH_BASE_URL/v1/models" >/dev/null 2>&1; then
      echo "ERROR: ornith handoff needs the local Ornith 1.0 35B MLX server on \$ORNITH_BASE_URL." >&2
      echo "Start the MLX server for leonsarmiento/Ornith-1.0-35B-4bit-mlx on that port, then retry." >&2
      exit 1
    fi
    exec env ANTHROPIC_BASE_URL="\$ORNITH_BASE_URL" ANTHROPIC_AUTH_TOKEN=mlx ANTHROPIC_API_KEY=mlx ANTHROPIC_MODEL="\$ORNITH_MODEL" ANTHROPIC_DEFAULT_OPUS_MODEL="\$ORNITH_MODEL" ANTHROPIC_DEFAULT_SONNET_MODEL="\$ORNITH_MODEL" ANTHROPIC_DEFAULT_HAIKU_MODEL="\$ORNITH_MODEL" CLAUDE_CODE_SUBAGENT_MODEL="\$ORNITH_MODEL" CLAUDE_CODE_DISABLE_1M_CONTEXT=1 CLAUDE_CODE_AUTO_COMPACT_WINDOW=10000 CLAUDE_CODE_ATTRIBUTION_HEADER=0 DISABLE_TELEMETRY=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 "\$TARGET_BIN" --bare --exclude-dynamic-system-prompt-sections --dangerously-skip-permissions --tools="" "\$PROMPT"
    ;;
  gemma-26)
    if ! curl -sf --max-time 2 "\$GEMMA_BASE_URL/v1/models" >/dev/null 2>&1; then
      echo "ERROR: gemma-26 handoff needs the local Gemma 4 26B MLX bridge on \$GEMMA_BASE_URL." >&2
      echo "Run 'claude-gemma-26' once in a terminal to boot the MLX server (:8774) + bridge (:8775), then retry." >&2
      exit 1
    fi
    exec env ANTHROPIC_BASE_URL="\$GEMMA_BASE_URL" ANTHROPIC_AUTH_TOKEN=mlx ANTHROPIC_API_KEY=mlx ANTHROPIC_MODEL="\$GEMMA_MODEL" ANTHROPIC_DEFAULT_OPUS_MODEL="\$GEMMA_MODEL" ANTHROPIC_DEFAULT_SONNET_MODEL="\$GEMMA_MODEL" ANTHROPIC_DEFAULT_HAIKU_MODEL="\$GEMMA_MODEL" CLAUDE_CODE_SUBAGENT_MODEL="\$GEMMA_MODEL" CLAUDE_CODE_DISABLE_1M_CONTEXT=1 CLAUDE_CODE_AUTO_COMPACT_WINDOW=10000 CLAUDE_CODE_ATTRIBUTION_HEADER=0 DISABLE_TELEMETRY=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 "\$TARGET_BIN" --bare --exclude-dynamic-system-prompt-sections --dangerously-skip-permissions "\$PROMPT"
    ;;
  grok)
    # --yolo auto-approves tool calls (alias of --always-approve / bypassPermissions).
    # Explicit deny rules and PreToolUse hooks still apply. --cwd is belt-and-suspenders
    # with the cd above; Terminal.app PATH quirks are already handled via absolute TARGET_BIN.
    GROK_ARGS=(--yolo --cwd "$WORK_DIR")
    if [ -n "\$GROK_MODEL" ]; then GROK_ARGS+=(--model "\$GROK_MODEL"); fi
    if [ -n "\$GROK_EFFORT" ]; then GROK_ARGS+=(--effort "\$GROK_EFFORT"); fi
    exec "\$TARGET_BIN" "\${GROK_ARGS[@]}" "\$PROMPT"
    ;;
esac
WRAPPEREOF

chmod 700 "$WRAPPER"

TINT=$(tint_color_for_session || true)

if [ -n "${TMUX:-}" ]; then
    tmux new-window -n "handoff-${TARGET}" "bash '$WRAPPER'"
    echo "SUCCESS: Handoff launched $TARGET in new tmux window" >&2
elif [ "${HANDOFF_NO_AUTO_SPAWN:-0}" != "1" ] && command -v osascript >/dev/null 2>&1; then
    # Tint the dispatching (main) window FIRST, then spawn the handoff window
    # already tinted to match. `do script` returns the new tab, so the tint
    # lands on the exact window we spawned -- no title matching (codex and
    # others overwrite the window title after exec).
    if [ -n "$TINT" ]; then
        tint_main_window "$TINT" || true
        IFS=',' read -r TINT_R TINT_G TINT_B <<< "$TINT"
    else
        TINT_R="" TINT_G="" TINT_B=""
    fi
    WRAPPER_CMD="bash $(quote_arg "$WRAPPER")"
    if ! osascript - "$WRAPPER_CMD" "$TINT_R" "$TINT_G" "$TINT_B" <<'APPLESCRIPT' >/dev/null 2>&1; then
on run argv
    set commandText to item 1 of argv
    tell application "Terminal"
        activate
        set newTab to do script commandText
        if (count of argv) >= 4 and (item 2 of argv) is not "" then
            try
                set r to (item 2 of argv) as integer
                set g to (item 3 of argv) as integer
                set b to (item 4 of argv) as integer
                set background color of newTab to {r, g, b}
            end try
        end if
    end tell
end run
APPLESCRIPT
        echo "ERROR: AppleScript Terminal launch failed. Run manually:" >&2
        echo "  bash '$WRAPPER'" >&2
        exit 1
    fi
    if [ -n "$TINT" ]; then
        echo "SUCCESS: Handoff launched $TARGET in new Terminal window (batch tint $TINT)" >&2
    else
        echo "SUCCESS: Handoff launched $TARGET in new Terminal window" >&2
    fi
else
    echo "MANUAL HANDOFF REQUIRED - run in a new terminal:" >&2
    echo "  bash '$WRAPPER'" >&2
fi
