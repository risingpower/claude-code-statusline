# Claude Code Statusline

A 4-line status bar for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows context usage, rate limits, and effort level at a glance.

![Lines overview](https://img.shields.io/badge/lines-4-blue)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)

## What it shows

```
Claude Opus 4.6 | 50k / 1.0m | 5% used 50,000 | 95% remain 950,000 | effort: high
current: ●●○○○○○○○○ 20%  | weekly: ●●●○○○○○○○ 30%  | extra: ●○○○○○○○○○ $1.20/$50.00
resets 3:45pm              | resets mar 15, 3:45pm    | resets apr 1
▸▸ bypass permissions off (shift+tab to cycle)
```

**Line 1** — Model name, context window tokens (used/total), percentage used & remaining with colour coding, current effort level. Context window is model-aware: Opus shows 1M, others show 200k.

**Line 2** — Rate limit progress bars: 5-hour (current), 7-day (weekly), and extra usage with dollar amounts (if enabled)

**Line 3** — Reset times for each rate limit window

**Line 4** — Current permission bypass mode

### Colour coding

| Colour | Meaning | Threshold |
|--------|---------|-----------|
| Green | Plenty of headroom | < 40% used (context) / < 80% (rate limits) |
| Amber | Getting warm | 40-69% used (context) / 80-89% (rate limits) |
| Red | Running low | 70%+ used (context) / 90%+ (rate limits) |

## Quick Install (paste into Claude Code)

Open Claude Code and paste this prompt:

```
Install the statusline from https://github.com/risingpower/claude-code-statusline:

1. Download statusline.sh from the repo to ~/.claude/statusline.sh and make it executable
2. Add the statusline command to ~/.claude/settings.json (merge with existing settings, don't overwrite):
   "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }
3. Extract my OAuth token for the usage bars:
   - macOS: security find-generic-password -s "Claude Code-credentials" -w | jq -r '.claudeAiOauth.accessToken'
   - Linux: jq -r '.claudeAiOauth.accessToken' ~/.claude/.credentials.json
4. Add the token as CLAUDE_OAUTH_TOKEN export to my shell profile (~/.zshrc or ~/.bashrc)
5. Confirm jq is installed (brew install jq / apt install jq if not)
```

That's it. Claude will handle the rest.

## Manual Install

<details>
<summary>If you prefer to do it yourself</summary>

### Requirements

- [jq](https://jqlang.github.io/jq/) — JSON processor (`brew install jq` or `apt install jq`)
- [curl](https://curl.se/) — for usage API calls (pre-installed on most systems)
- Claude Code CLI

### 1. Copy the script

```bash
mkdir -p ~/.claude
curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/risingpower/claude-code-statusline/main/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Or clone and symlink:

```bash
git clone https://github.com/risingpower/claude-code-statusline.git
ln -sf "$(pwd)/claude-code-statusline/statusline.sh" ~/.claude/statusline.sh
```

### 2. Enable in Claude Code settings

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

### 3. (Optional) Enable usage bars

Lines 2 and 3 show rate limit progress bars. These require an OAuth token to call the Anthropic usage API.

Set the token in your shell profile (`~/.zshrc`, `~/.bashrc`, etc.):

```bash
export CLAUDE_OAUTH_TOKEN="your-oauth-token-here"
```

**To get your token:**

On **macOS**, your Claude Code OAuth token is stored in Keychain. You can extract it with:

```bash
security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken'
```

On **Linux**, check `~/.claude/.credentials.json`:

```bash
jq -r '.claudeAiOauth.accessToken' ~/.claude/.credentials.json
```

> **Note:** OAuth tokens expire and rotate. If the usage bars stop working, re-extract a fresh token. Without a token, lines 2-3 are simply hidden — line 1 and 4 always work.

</details>

## Customisation

The script is plain bash — edit it to suit your taste. Some ideas:

- Change the bar characters (`●` / `○`) to something else
- Adjust colour thresholds
- Remove lines you don't need
- Change the bar width (default: 10 characters)

## License

MIT
