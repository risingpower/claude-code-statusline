#!/bin/bash
# Claude Code 4-line status bar
# Line 1: Model | tokens used/total | % used <count> | % remain <count> | effort: <level>
# Line 2: current: <bar> % | weekly: <bar> % | extra: <bar> $used/$limit
# Line 3: resets <time> | resets <datetime> | resets <date>
# Line 4: >> bypass permissions on/off (shift+tab to cycle)
#
# Install:
#   1. Copy this file to ~/.claude/statusline.sh
#   2. chmod +x ~/.claude/statusline.sh
#   3. Add to ~/.claude/settings.json:
#        "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }
#   4. (Optional) For usage bars, set CLAUDE_OAUTH_TOKEN in your shell profile.
#      See README.md for how to obtain your token.

set -f  # disable globbing

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# -- Colours (6-colour palette) -----------------------------------------------
# Three data colours (green=good, amber=caution, red=danger), one accent,
# bright for neutral data, dim for everything structural.
bright='\033[38;2;210;215;224m'      # #D2D7E0 - primary data values
dim='\033[38;2;110;118;129m'         # #6E7681 - labels, separators, hints, resets
accent='\033[38;2;255;255;255m'      # #FFFFFF - model name only
soft_green='\033[38;2;90;199;120m'   # #5AC778 - good / capacity
soft_amber='\033[38;2;210;170;90m'   # #D2AA5A - caution / consumption
soft_red='\033[38;2;220;100;100m'    # #DC6464 - danger / critical
reset='\033[0m'

# Format token counts (e.g., 50k, 200k, 1.0m)
format_tokens() {
    local num=$1
    if [ "$num" -ge 1000000 ]; then
        awk "BEGIN {printf \"%.1fm\", $num / 1000000}"
    elif [ "$num" -ge 1000 ]; then
        awk "BEGIN {printf \"%.0fk\", $num / 1000}"
    else
        printf "%d" "$num"
    fi
}

# Format number with commas (e.g., 134,938)
format_commas() {
    printf "%'d" "$1"
}

# Build a progress bar with threshold-based colours
# Dots match the % indicator: bright <80%, amber 80-89%, red 90%+
# Usage: build_bar <pct> <width>
build_bar() {
    local pct=$1
    local width=$2
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local fill_color
    if [ "$pct" -ge 90 ]; then fill_color="$soft_red"
    elif [ "$pct" -ge 80 ]; then fill_color="$soft_amber"
    else fill_color="$bright"
    fi

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))

    local filled_str="" empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="●"; done
    for ((i=0; i<empty; i++)); do empty_str+="○"; done

    printf "${fill_color}${filled_str}${dim}${empty_str}${reset}"
}

# ===== Extract data from JSON =====
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')
perm_mode=$(echo "$input" | jq -r '.permission_mode // "default"')

# Context window
size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
if [ "$size" -eq 0 ] 2>/dev/null; then
    size=200000
fi

# Token usage
input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
current=$(( input_tokens + cache_create + cache_read ))

used_tokens=$(format_tokens $current)
total_tokens=$(format_tokens $size)

if [ "$size" -gt 0 ]; then
    pct_used=$(( current * 100 / size ))
else
    pct_used=0
fi
pct_remain=$(( 100 - pct_used ))

used_comma=$(format_commas $current)
remain_comma=$(format_commas $(( size - current )))

# Read effort level from settings
effort_level="default"
settings_path="$HOME/.claude/settings.json"
if [ -f "$settings_path" ]; then
    effort_val=$(jq -r '.effortLevel // empty' "$settings_path" 2>/dev/null)
    [ -n "$effort_val" ] && [ "$effort_val" != "null" ] && effort_level="$effort_val"
fi

# ===== LINE 1: Model | tokens | % used | % remain | effort =====
line1=""
line1+="${accent}${model_name}${reset}"
line1+=" ${dim}|${reset} "
line1+="${bright}${used_tokens} / ${total_tokens}${reset}"
line1+=" ${dim}|${reset} "
# Dynamic colour for used %: <40 green, 40-69 amber, 70+ red
if [ "$pct_used" -ge 70 ]; then used_color="$soft_red"
elif [ "$pct_used" -ge 40 ]; then used_color="$soft_amber"
else used_color="$soft_green"
fi
# Inverse for remain %: >60 green, 31-60 amber, <=30 red
if [ "$pct_remain" -le 30 ]; then remain_color="$soft_red"
elif [ "$pct_remain" -le 60 ]; then remain_color="$soft_amber"
else remain_color="$soft_green"
fi
line1+="${used_color}${pct_used}% used ${used_comma}${reset}"
line1+=" ${dim}|${reset} "
line1+="${remain_color}${pct_remain}% remain ${remain_comma}${reset}"
line1+=" ${dim}|${reset} "
line1+="${dim}effort:${reset} "
line1+="${bright}${effort_level}${reset}"

# ===== Usage API token =====
# Set CLAUDE_OAUTH_TOKEN in your shell profile to enable usage bars.
# See README.md for instructions on obtaining your token.
token="${CLAUDE_OAUTH_TOKEN:-}"

# ===== LINE 2 & 3: Usage limits with progress bars (cached) =====
cache_file="/tmp/claude/statusline-usage-cache.json"
cache_max_age=60
mkdir -p /tmp/claude

needs_refresh=true
usage_data=""

# Check cache
if [ -f "$cache_file" ]; then
    cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
    now=$(date +%s)
    cache_age=$(( now - cache_mtime ))
    if [ "$cache_age" -lt "$cache_max_age" ]; then
        needs_refresh=false
        usage_data=$(cat "$cache_file" 2>/dev/null)
    fi
fi

# Fetch fresh data if cache is stale
if $needs_refresh; then
    if [ -n "$token" ]; then
        response=$(curl -s --max-time 5 \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        if [ -n "$response" ] && echo "$response" | jq . >/dev/null 2>&1; then
            usage_data="$response"
            echo "$response" > "$cache_file"
        fi
    fi
    # Fall back to stale cache
    if [ -z "$usage_data" ] && [ -f "$cache_file" ]; then
        usage_data=$(cat "$cache_file" 2>/dev/null)
    fi
fi

# Cross-platform ISO to epoch conversion
iso_to_epoch() {
    local iso_str="$1"

    # Try GNU date first (Linux)
    local epoch
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    # BSD date (macOS)
    local stripped="${iso_str%%.*}"
    stripped="${stripped%%Z}"
    stripped="${stripped%%+*}"
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"

    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]] || [[ "$iso_str" == *"-00:00"* ]]; then
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    fi

    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    return 1
}

# Format ISO reset time to compact local time
format_reset_time() {
    local iso_str="$1"
    local style="$2"
    [ -z "$iso_str" ] || [ "$iso_str" = "null" ] && return

    local epoch
    epoch=$(iso_to_epoch "$iso_str")
    [ -z "$epoch" ] && return

    case "$style" in
        time)
            date -j -r "$epoch" +"%l:%M%p" 2>/dev/null | sed 's/^ //' | tr '[:upper:]' '[:lower:]' || \
            date -d "@$epoch" +"%l:%M%P" 2>/dev/null | sed 's/^ //'
            ;;
        datetime)
            date -j -r "$epoch" +"%b %-d, %l:%M%p" 2>/dev/null | sed 's/  / /g; s/^ //' | tr '[:upper:]' '[:lower:]' || \
            date -d "@$epoch" +"%b %-d, %l:%M%P" 2>/dev/null | sed 's/  / /g; s/^ //'
            ;;
        *)
            date -j -r "$epoch" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]' || \
            date -d "@$epoch" +"%b %-d" 2>/dev/null
            ;;
    esac
}

# Pad column to fixed width (ignoring ANSI codes)
pad_column() {
    local text="$1"
    local visible_len=$2
    local col_width=$3
    local padding=$(( col_width - visible_len ))
    if [ "$padding" -gt 0 ]; then
        printf "%s%*s" "$text" "$padding" ""
    else
        printf "%s" "$text"
    fi
}

line2=""
line3=""
sep=" ${dim}|${reset} "

if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
    bar_width=10
    col1w=23
    col2w=22

    # ---- 5-hour (current) ----
    five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
    five_hour_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
    five_hour_reset=$(format_reset_time "$five_hour_reset_iso" "time")
    five_hour_bar=$(build_bar "$five_hour_pct" "$bar_width")

    if [ "$five_hour_pct" -ge 90 ]; then five_hour_pct_color="$soft_red"
    elif [ "$five_hour_pct" -ge 80 ]; then five_hour_pct_color="$soft_amber"
    else five_hour_pct_color="$bright"
    fi
    col1_bar_vis_len=$(( 9 + bar_width + 1 + ${#five_hour_pct} + 1 ))
    col1_bar="${dim}current:${reset} ${five_hour_bar} ${five_hour_pct_color}${five_hour_pct}%${reset}"
    col1_bar=$(pad_column "$col1_bar" "$col1_bar_vis_len" "$col1w")

    col1_reset_plain="resets ${five_hour_reset}"
    col1_reset="${dim}resets ${five_hour_reset}${reset}"
    col1_reset=$(pad_column "$col1_reset" "${#col1_reset_plain}" "$col1w")

    # ---- 7-day (weekly) ----
    seven_day_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
    seven_day_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
    seven_day_reset=$(format_reset_time "$seven_day_reset_iso" "datetime")
    seven_day_bar=$(build_bar "$seven_day_pct" "$bar_width")

    if [ "$seven_day_pct" -ge 90 ]; then seven_day_pct_color="$soft_red"
    elif [ "$seven_day_pct" -ge 80 ]; then seven_day_pct_color="$soft_amber"
    else seven_day_pct_color="$bright"
    fi
    col2_bar_vis_len=$(( 8 + bar_width + 1 + ${#seven_day_pct} + 1 ))
    col2_bar="${dim}weekly:${reset} ${seven_day_bar} ${seven_day_pct_color}${seven_day_pct}%${reset}"
    col2_bar=$(pad_column "$col2_bar" "$col2_bar_vis_len" "$col2w")

    col2_reset_plain="resets ${seven_day_reset}"
    col2_reset="${dim}resets ${seven_day_reset}${reset}"
    col2_reset=$(pad_column "$col2_reset" "${#col2_reset_plain}" "$col2w")

    # ---- Extra usage ----
    col3_bar=""
    col3_reset=""
    extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
    if [ "$extra_enabled" = "true" ]; then
        extra_pct=$(echo "$usage_data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
        extra_used=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0' | awk '{printf "%.2f", $1/100}')
        extra_limit=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0' | awk '{printf "%.2f", $1/100}')
        extra_bar=$(build_bar "$extra_pct" "$bar_width")
        extra_reset=$(date -v+1m -v1d +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')

        col3_bar="${dim}extra:${reset} ${extra_bar} ${bright}\$${extra_used}/\$${extra_limit}${reset}"
        col3_reset="${dim}resets ${extra_reset}${reset}"
    fi

    # Assemble line 2: bars row
    line2="${col1_bar}${sep}${col2_bar}"
    [ -n "$col3_bar" ] && line2+="${sep}${col3_bar}"

    # Assemble line 3: resets row
    line3="${col1_reset}${sep}${col2_reset}"
    [ -n "$col3_reset" ] && line3+="${sep}${col3_reset}"
fi

# ===== LINE 4: Permissions Mode =====
case "$perm_mode" in
    "bypassPermissions"|"dontAsk")
        perm_label="on"
        ;;
    *)
        perm_label="off"
        ;;
esac

line4="${dim}▸▸ bypass permissions${reset} ${bright}${perm_label}${reset} ${dim}(shift+tab to cycle)${reset}"

# ===== Output =====
printf "%b" "$line1"
[ -n "$line2" ] && printf "\n%b" "$line2"
[ -n "$line3" ] && printf "\n%b" "$line3"
printf "\n%b" "$line4"

exit 0
