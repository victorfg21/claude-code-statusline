#!/usr/bin/env bash

readonly FIELD_DELIMITER="|"
readonly FALLBACK_OUTPUT="Unknown|~|0|200000|0|0.0000|0|-|-|0|0"
readonly DEFAULT_COLS=120
readonly DEFAULT_CONTEXT_SIZE=200000
readonly BAR_WIDTH=10
readonly BAR_CHAR_FILLED="▓"
readonly BAR_CHAR_EMPTY="░"
readonly PATH_TRUNCATION_RATIO=3
readonly PATH_MIN_LENGTH=10
readonly PATH_ELLIPSIS=".."
readonly WIDE_LAYOUT_MIN_COLS=100
readonly SECONDS_PER_MINUTE=60
readonly MINUTES_PER_HOUR=60
readonly MS_PER_SECOND=1000
readonly TOKENS_PER_MILLION=1000000
readonly TOKENS_PER_THOUSAND=1000
readonly THRESHOLD_CRITICAL=90
readonly THRESHOLD_WARNING=70
readonly THRESHOLD_RATE_HIGH=80
readonly THRESHOLD_RATE_MID=50
readonly RATE_UNAVAILABLE="-"
readonly COST_DECIMAL_PLACES=4

readonly CAVEMAN_FLAG_FILE=".caveman-active"
readonly CAVEMAN_SAVINGS_FILE=".caveman-statusline-suffix"
readonly CAVEMAN_FLAG_MAX_BYTES=64
readonly CAVEMAN_VALID_MODES="off lite full ultra wenyan-lite wenyan wenyan-full wenyan-ultra commit review compress"

readonly RESET=$'\033[0m'
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'
readonly FG_CYAN=$'\033[36m'
readonly FG_YELLOW=$'\033[33m'
readonly FG_GREEN=$'\033[32m'
readonly FG_RED=$'\033[31m'
readonly FG_MAGENTA=$'\033[35m'
readonly FG_BLUE=$'\033[34m'
readonly FG_GRAY=$'\033[90m'
readonly FG_ORANGE=$'\033[38;5;172m'
readonly OSC=$'\033]'
readonly BEL=$'\007'

terminal_width() {
    echo "${COLUMNS:-$(tput cols 2>/dev/null || echo "$DEFAULT_COLS")}"
}

parse_session_data() {
    local raw_input="$1"

    echo "$raw_input" | node -e "
const chunks = [];
process.stdin.on('data', c => chunks.push(c));
process.stdin.on('end', () => {
  try {
    const d = JSON.parse(chunks.join(''));
    const model = (d.model || {}).display_name || 'Unknown';
    const cwd = ((d.workspace || {}).current_dir || d.cwd || '~').replace(/\\\\\\\\/g, '/');
    const contextWindow = d.context_window || {};
    const currentUsage = contextWindow.current_usage || {};
    const contextSize = contextWindow.context_window_size || ${DEFAULT_CONTEXT_SIZE};

    let usedTokens = (currentUsage.input_tokens || 0)
        + (currentUsage.cache_creation_input_tokens || 0)
        + (currentUsage.cache_read_input_tokens || 0);
    if (usedTokens === 0) usedTokens = contextWindow.total_input_tokens || 0;

    const usedPercent = contextSize > 0 && usedTokens > 0
        ? Math.floor(usedTokens / contextSize * 100) : 0;
    const cost = ((d.cost || {}).total_cost_usd || 0).toFixed(${COST_DECIMAL_PLACES});
    const durationMs = (d.cost || {}).total_duration_ms || 0;
    const rateLimits = d.rate_limits || {};
    const rateLimit5h = (rateLimits.five_hour || {}).used_percentage;
    const rateLimit7d = (rateLimits.seven_day || {}).used_percentage;
    const linesAdded = (d.cost || {}).total_lines_added || 0;
    const linesRemoved = (d.cost || {}).total_lines_removed || 0;

    process.stdout.write([
        model, cwd, usedTokens, contextSize, usedPercent, cost,
        durationMs,
        rateLimit5h != null ? Math.round(rateLimit5h) : '${RATE_UNAVAILABLE}',
        rateLimit7d != null ? Math.round(rateLimit7d) : '${RATE_UNAVAILABLE}',
        linesAdded, linesRemoved
    ].join('${FIELD_DELIMITER}') + '\n');
  } catch(e) {
    process.stdout.write('${FALLBACK_OUTPUT}\n');
  }
});
"
}

extract_field() {
    local data="$1"
    local position="$2"
    echo "$data" | cut -d"${FIELD_DELIMITER}" -f"$position"
}

shorten_home_path() {
    local full_path="$1"
    local username="${HOME##*/}"
    local patterns=("$HOME" "/c/Users/$username" "C:/Users/$username" "C:\\Users\\$username")

    for pattern in "${patterns[@]}"; do
        if [[ "$full_path" == "$pattern"* ]]; then
            local suffix="${full_path#$pattern}"
            echo "~${suffix//\\//}"
            return
        fi
    done

    echo "$full_path"
}

path_to_file_url() {
    local raw_path="$1"
    local normalized="${raw_path//\\//}"

    case "$normalized" in
        /c/*) echo "file:///C:/${normalized#/c/}" ;;
        /d/*) echo "file:///D:/${normalized#/d/}" ;;
        [A-Z]:*) echo "file:///${normalized}" ;;
        /*) echo "file://${normalized}" ;;
        *) echo "file:///${normalized}" ;;
    esac
}

wrap_osc8_link() {
    local url="$1"
    local label="$2"
    local color="$3"
    echo "${color}${OSC}8;;${url}${BEL}${label}${OSC}8;;${BEL}${RESET}"
}

truncate_path() {
    local path="$1"
    local cols="$2"
    local max_length=$(( cols / PATH_TRUNCATION_RATIO ))

    if [ "${#path}" -le "$max_length" ] || [ "$max_length" -le "$PATH_MIN_LENGTH" ]; then
        echo "$path"
        return
    fi

    echo "${PATH_ELLIPSIS}${path: -$(( max_length - ${#PATH_ELLIPSIS} ))}"
}

resolve_git_branch() {
    local dir="$1"
    git -C "$dir" symbolic-ref --short HEAD 2>/dev/null \
        || git -C "$dir" rev-parse --short HEAD 2>/dev/null \
        || echo "detached"
}

count_git_changes() {
    local dir="$1"
    local diff_args="$2"
    git -C "$dir" diff $diff_args --name-only 2>/dev/null | wc -l | tr -d ' '
}

build_git_indicators() {
    local staged="$1"
    local modified="$2"
    local result=""

    [ "$staged" -gt 0 ] && result+=" ${FG_GREEN}+${staged}${RESET}"
    [ "$modified" -gt 0 ] && result+=" ${FG_YELLOW}~${modified}${RESET}"
    [ -z "$result" ] && result=" ${FG_GREEN}clean${RESET}"

    echo "$result"
}

ssh_to_https_url() {
    local url="$1"

    if [[ "$url" != git@* ]]; then
        echo "${url%.git}"
        return
    fi

    local converted="${url#git@}"
    converted="${converted/://}"
    echo "https://${converted%.git}"
}

build_repo_link() {
    local dir="$1"
    local remote_url
    remote_url=$(git -C "$dir" remote get-url origin 2>/dev/null || true)

    if [ -z "$remote_url" ]; then
        return
    fi

    local https_url
    https_url=$(ssh_to_https_url "$remote_url")
    local repo_label
    repo_label=$(echo "$https_url" | sed 's|.*/\([^/]*/[^/]*\)$|\1|')

    echo " $(wrap_osc8_link "$https_url" "$repo_label" "$FG_CYAN")"
}

build_git_segment() {
    local dir="$1"

    if ! git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        return
    fi

    local branch
    branch=$(resolve_git_branch "$dir")
    local staged
    staged=$(count_git_changes "$dir" "--cached")
    local modified
    modified=$(count_git_changes "$dir" "")
    local indicators
    indicators=$(build_git_indicators "$staged" "$modified")

    echo " ${DIM}on${RESET} ${FG_MAGENTA}${BOLD}${branch}${RESET}${indicators}"
}

format_tokens() {
    local count=${1:-0}

    if [ "$count" -ge "$TOKENS_PER_MILLION" ]; then
        awk "BEGIN {printf \"%.1fM\", $count/$TOKENS_PER_MILLION}"
    elif [ "$count" -ge "$TOKENS_PER_THOUSAND" ]; then
        echo "$(( count / TOKENS_PER_THOUSAND ))k"
    else
        echo "$count"
    fi
}

color_by_threshold() {
    local value="$1"

    if [ "$value" -ge "$THRESHOLD_CRITICAL" ]; then
        echo "$FG_RED"
    elif [ "$value" -ge "$THRESHOLD_WARNING" ]; then
        echo "$FG_YELLOW"
    else
        echo "$FG_GREEN"
    fi
}

build_progress_bar() {
    local percent="$1"
    local color="$2"
    local filled=$(( percent * BAR_WIDTH / 100 ))
    local empty=$(( BAR_WIDTH - filled ))
    local bar=""

    for (( i = 0; i < filled; i++ )); do bar+="$BAR_CHAR_FILLED"; done
    for (( i = 0; i < empty; i++ )); do bar+="$BAR_CHAR_EMPTY"; done

    local filled_part="${bar:0:$filled}"
    local empty_part="${bar:$filled}"

    echo "${color}${filled_part}${DIM}${empty_part}${RESET}"
}

format_duration() {
    local total_ms=${1:-0}
    local total_sec=$(( total_ms / MS_PER_SECOND ))
    local minutes=$(( total_sec / SECONDS_PER_MINUTE ))
    local seconds=$(( total_sec % SECONDS_PER_MINUTE ))

    if [ "$minutes" -ge "$MINUTES_PER_HOUR" ]; then
        echo "$(( minutes / MINUTES_PER_HOUR ))h$(( minutes % MINUTES_PER_HOUR ))m"
    else
        echo "${minutes}m${seconds}s"
    fi
}

format_rate_limit() {
    local value="$1"
    local label="$2"

    if [ "$value" = "$RATE_UNAVAILABLE" ]; then
        echo "${DIM}${label}:--${RESET}"
        return
    fi

    local color="$FG_GREEN"
    [ "$value" -ge "$THRESHOLD_RATE_MID" ] && color="$FG_YELLOW"
    [ "$value" -ge "$THRESHOLD_RATE_HIGH" ] && color="$FG_RED"

    echo "${color}${label}:${value}%${RESET}"
}

format_lines_changed() {
    local added=${1:-0}
    local removed=${2:-0}

    if [ "$added" -eq 0 ] && [ "$removed" -eq 0 ]; then
        return
    fi

    echo "${FG_GREEN}+${added}${RESET}${FG_RED}-${removed}${RESET}"
}

read_caveman_mode() {
    local claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    local flag="$claude_dir/$CAVEMAN_FLAG_FILE"
    [ -f "$flag" ] || return

    local size
    size=$(wc -c <"$flag" 2>/dev/null | tr -d ' ')
    [ "${size:-0}" -gt "$CAVEMAN_FLAG_MAX_BYTES" ] && return

    local raw
    raw=$(head -n 1 "$flag" 2>/dev/null | tr -d '\r\n' | tr '[:upper:]' '[:lower:]')
    raw="${raw//[^a-z0-9-]/}"
    [ -z "$raw" ] && return

    local mode
    for mode in $CAVEMAN_VALID_MODES; do
        [ "$raw" = "$mode" ] && { printf '%s' "$raw"; return; }
    done
}

read_caveman_savings() {
    [ "${CAVEMAN_STATUSLINE_SAVINGS:-1}" = "0" ] && return
    local claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    local file="$claude_dir/$CAVEMAN_SAVINGS_FILE"
    [ -f "$file" ] || return

    local size
    size=$(wc -c <"$file" 2>/dev/null | tr -d ' ')
    [ "${size:-0}" -gt "$CAVEMAN_FLAG_MAX_BYTES" ] && return

    local raw
    raw=$(tr -d '\000-\037' <"$file" 2>/dev/null)
    [ -n "$raw" ] && printf '%s' "$raw"
}

build_caveman_segment() {
    local mode
    mode=$(read_caveman_mode)
    [ -z "$mode" ] && return

    local label
    if [ "$mode" = "full" ]; then
        label="[CAVEMAN]"
    else
        label="[CAVEMAN:$(echo "$mode" | tr '[:lower:]' '[:upper:]')]"
    fi

    local savings
    savings=$(read_caveman_savings)
    if [ -n "$savings" ]; then
        echo "  ${FG_ORANGE}${label} ${savings}${RESET}"
    else
        echo "  ${FG_ORANGE}${label}${RESET}"
    fi
}

render_wide() {
    local display_dir="$1" git_segment="$2" repo_link="$3"
    local context_bar="$4" cost="$5" duration="$6"
    local lines_changed="$7" rate_5h="$8" rate_7d="$9" model_name="${10}"
    local dir_url="${11}" caveman_segment="${12}"

    local dir_label
    dir_label=$(wrap_osc8_link "$dir_url" "$display_dir" "${FG_BLUE}${BOLD}")
    printf '%s\n' " ${dir_label}${git_segment}${repo_link}"

    local metrics=" ${context_bar}  ${FG_GRAY}\$${cost}${RESET}  ${DIM}${duration}${RESET}"
    [ -n "$lines_changed" ] && metrics+="  ${lines_changed}"
    metrics+="  ${rate_5h} ${rate_7d}  ${DIM}${model_name}${RESET}${caveman_segment}"

    printf '%s\n' "$metrics"
}

render_narrow() {
    local display_dir="$1" git_segment="$2"
    local context_bar="$3" cost="$4" duration="$5"
    local lines_changed="$6" rate_5h="$7" rate_7d="$8" model_name="${9}"
    local dir_url="${10}" caveman_segment="${11}"

    local dir_label
    dir_label=$(wrap_osc8_link "$dir_url" "$display_dir" "${FG_BLUE}${BOLD}")
    printf '%s\n' " ${dir_label}${git_segment}"
    printf '%s\n' " ${context_bar}  ${FG_GRAY}\$${cost}${RESET}  ${DIM}${duration}${RESET}"

    local bottom=" ${rate_5h} ${rate_7d}  ${DIM}${model_name}${RESET}${caveman_segment}"
    [ -n "$lines_changed" ] && bottom=" ${lines_changed}  ${rate_5h} ${rate_7d}  ${DIM}${model_name}${RESET}${caveman_segment}"

    printf '%s\n' "$bottom"
}

main() {
    local cols
    cols=$(terminal_width)

    local raw_input
    raw_input=$(cat)

    local parsed
    parsed=$(parse_session_data "$raw_input")

    local model
    model=$(extract_field "$parsed" 1)
    local current_dir
    current_dir=$(extract_field "$parsed" 2)
    local used_tokens
    used_tokens=$(extract_field "$parsed" 3)
    local ctx_size
    ctx_size=$(extract_field "$parsed" 4)
    local used_pct
    used_pct=$(extract_field "$parsed" 5)
    local cost_usd
    cost_usd=$(extract_field "$parsed" 6)
    local duration_ms
    duration_ms=$(extract_field "$parsed" 7)
    local rate_5h
    rate_5h=$(extract_field "$parsed" 8)
    local rate_7d
    rate_7d=$(extract_field "$parsed" 9)
    local lines_added
    lines_added=$(extract_field "$parsed" 10)
    local lines_removed
    lines_removed=$(extract_field "$parsed" 11)

    local display_dir
    display_dir=$(shorten_home_path "$current_dir")
    display_dir=$(truncate_path "$display_dir" "$cols")
    local dir_url
    dir_url=$(path_to_file_url "$current_dir")

    local git_segment
    git_segment=$(build_git_segment "$current_dir")
    local repo_link
    repo_link=$(build_repo_link "$current_dir")

    local bar_color
    bar_color=$(color_by_threshold "${used_pct:-0}")
    local progress_bar
    progress_bar=$(build_progress_bar "${used_pct:-0}" "$bar_color")
    local used_fmt
    used_fmt=$(format_tokens "${used_tokens:-0}")
    local total_fmt
    total_fmt=$(format_tokens "${ctx_size:-$DEFAULT_CONTEXT_SIZE}")
    local context_bar="${progress_bar} ${bar_color}${BOLD}${used_pct:-0}%${RESET} ${FG_GRAY}${used_fmt}/${total_fmt}${RESET}"

    local duration
    duration=$(format_duration "$duration_ms")
    local rate_5h_fmt
    rate_5h_fmt=$(format_rate_limit "$rate_5h" "5h")
    local rate_7d_fmt
    rate_7d_fmt=$(format_rate_limit "$rate_7d" "7d")
    local lines_changed
    lines_changed=$(format_lines_changed "$lines_added" "$lines_removed")
    local caveman_segment
    caveman_segment=$(build_caveman_segment)

    if [ "$cols" -ge "$WIDE_LAYOUT_MIN_COLS" ]; then
        render_wide "$display_dir" "$git_segment" "$repo_link" \
            "$context_bar" "$cost_usd" "$duration" \
            "$lines_changed" "$rate_5h_fmt" "$rate_7d_fmt" "$model" "$dir_url" \
            "$caveman_segment"
    else
        render_narrow "$display_dir" "$git_segment" \
            "$context_bar" "$cost_usd" "$duration" \
            "$lines_changed" "$rate_5h_fmt" "$rate_7d_fmt" "$model" "$dir_url" \
            "$caveman_segment"
    fi
}

main
