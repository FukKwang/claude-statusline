# claude-statusline

A colorful status line for [Claude Code](https://claude.com/claude-code). It shows your plan limits, cost and tokens at a glance, fits narrow panes, and in tight panes shows context and cache only when they need attention.

Two lines in a normal pane:

```
✻ Opus 5.5   5h ▰▰▰▱ 62% +9 ↻ 14:32   wk ▰▰▰▰ 92% +3 ↻ Wed 20:00
◐ 18% left   $12.35   tok main 1.2M (O1.2M) + sub 3.4M (S3.3M H98k) = 4.6M   ⛁ cache 1m left
```

## What it shows

| Item | Meaning |
|------|---------|
| `✻ Opus 5.5` | Current model |
| `5h 62%` | 5-hour limit used. The bar appears from 50% used (always in wide panes) |
| `wk 92%` | Weekly limit used. The bar appears from 50% used (always in wide panes) |
| `+9` | How much of that limit this Claude Code session used (see below) |
| `↻ 14:32` | When the limit resets, in local time (`↻ Wed 20:00` when more than a day away). The paragraph says `resets in 2h 12m` instead |
| `◐ 18% left` | Context window left. Appears only below 30%, except in wide panes |
| `$12.35` | Session cost in USD |
| `tok 4.6M` | Session tokens: input + cache write + cache read + output, summed over every API call in the transcripts. Subagents (nested ones too) are read from `<session>/subagents/` |
| `tok main 1.2M (O1.2M) + sub 3.4M (S3.3M H98k) = 4.6M` | Tokens of the main thread and of subagents, each per model (largest first), and the total. Without subagents: `tok 1.2M (O1.2M)`. `F` Fable, `O` Opus, `S` Sonnet, `H` Haiku |
| `⛁ cache` | Appears only when the prompt cache expires within 2 minutes (`1m left`), has expired (`expired`: the next message rebuilds it), or the last hit rate was below 80% (`hit 62%`) |

Colors: green, then amber from 50%, then red from 80%.

## Width

Several Claude Code panes side by side leave each one a narrow terminal. The script measures the width and prints the most detailed layout that fits (layouts 0-5), or the paragraph (6) in a pane of 65 columns or less:

0. Wide panes: everything, including the quiet items all the time (limit bars, context, cache hit rate and time left, tokens per model), on one line or two:

```
✻ Opus 5.5   5h ▰▱▱▱ 35% +9 ↻ 09:10   wk ▰▰▰▰ 94% +2 ↻ Wed 20:00
◐ ctx ▱▱▱▱ 88% left   $3.93   tok main 7.1M (O7.1M) + sub 32.7M (S32.6M H98k) = 39.8M   ⛁ cache 99% hit · 59m left
```

1. Everything on one line, quiet items only when they need attention.
2. Account line (model, limits) and session line (context, cost, tokens), as above.
3. The same two lines without the per-model split.
4. As 3, without the model name.
5. One compact line: `5h 62%   wk 92%   ◐ 18% left   $12.35   tok 4.6M`.
6. A short paragraph, word-wrapped to the pane. Panes 65 columns wide or narrower always get this (set `paragraph_cols` in the script):

```
You've used 62% of your 5-hour limit
(9% in this chat); it resets in
2h 42m. The week is at 92% (3% here)
and resets in 2d 13h. This chat cost
$1.20 for 39.8M tokens. Context is
down to 18%. The cache has expired.
```

Every item stays in the same place, so you can find it at a glance.

## `+N`: this session's share of a limit

`+N` is how much the limit went up since this session first saw the window. The script saves that start value in `~/.cache/claude-statusline/<session id>.json` (files older than 8 days are deleted). It is an estimate:
- Other sessions running at the same time also raise the limit, and that counts as `+N`.
- The limit arrives with the first API response, so the session's first request is not counted.
- Claude Code reports whole percents, so `+N` moves in 1% steps.
- When the window resets, `+N` counts from 0 again.

The 5h and weekly limits appear only when you sign in with a Claude Pro or Max plan. On a subscription, the cost is the API-equivalent value, not what you pay.

## Requirements

- Claude Code
- `bash` and `jq`

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/FukKwang/claude-statusline/main/statusline.sh -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Then add this to `~/.claude/settings.json`:

```json
{
  "statusLine": { "type": "command", "command": "~/.claude/statusline.sh", "refreshInterval": 30 }
}
```

The status line appears after your next message.

## Customize

- Colors: edit the `38;5;N` codes (256-color palette) in `statusline.sh`.
- Thresholds: edit the `heat` function (colors), `$ctx` (context alert) and `cache` (cache alerts).

## License

MIT
