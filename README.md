# claude-statusline

A colorful status line for [Claude Code](https://claude.com/claude-code). It always shows the four things that matter most: context left, prompt cache time left, session tokens, and this session's share of the 5-hour limit. Other items appear only when the pane has room.

A wide pane:

```
✻ Opus 5.5   ◐ context ▰▱▱▱ 72%   ⛁ cache 59m · 94% hit   Σ tokens 74k (O 74k)   5h ▰▰▰▱ 63% +9% ↻ 16:06   wk ▰▱▱▱ 20% +0% ↻ Wed 21:43   $3.90
```

A narrow pane:

```
◐ 72%   ⛁ 59m   Σ 74k   5h 63% +9%
```

## What it shows

| Item | Meaning |
|------|---------|
| `◐ 72%` | Context window left. **Always shown** |
| `⛁ 59m` | Time until the prompt cache expires (`expired`: the next message rebuilds it). **Always shown** |
| `Σ 74k` | Session tokens: input + cache write + output, summed over every API call in the transcripts. Cache reads are left out, because every call re-reads the whole context. Subagents (nested ones too) are read from `<session>/subagents/`. **Always shown** |
| `5h +9%` | How much of the 5-hour limit this Claude Code session used (see below). **Always shown** |
| `5h 63%` | 5-hour limit used in total |
| `wk 20% +0%` | Weekly limit used, and this session's share |
| `✻ Opus 5.5` | Current model |
| `Σ tokens main 120k (O 120k) + subagents 340k (S 330k, H 9k) = 460k` | Tokens of the main thread and of subagents, each per model (largest first), and the total. Without subagents: `Σ tokens 120k (O 120k)`. `F` Fable, `O` Opus, `S` Sonnet, `H` Haiku |
| `▰▰▰▱` | Bars for context and limits |
| `$3.90` | Session cost in USD |
| `94% hit` | Cache hit rate of the last request |
| `↻ 16:06` | When the limit resets, in local time (`↻ Wed 21:43` when more than a day away) |

Colors: green, then amber from 50%, then red from 80%. The cache time is amber below 2 minutes and red when expired.

## Width

Several Claude Code panes side by side leave each one a narrow terminal. The script measures the width and starts with the short form of the four core items: icons only (`◐ 72%   ⛁ 59m   Σ 74k   5h +9%`). They always show; in a very narrow pane they wrap onto a second line. Then, in this order, items grow or appear while everything still fits on the same number of lines:

1. Words next to the icons (`◐ context 72%`, `⛁ cache 59m`, `Σ tokens 74k`)
2. Total 5h use (`5h 63% +9%`), then the weekly limit
3. Model name
4. Tokens per model
5. Bars
6. Cost
7. Cache hit rate
8. Reset times

Items keep the same order on the line, so you can find them at a glance. To change the priority, edit `$steps` in the script.

## `+N%`: this session's share of a limit

`+N%` is how much the limit went up since this session first saw the window. The script saves that start value in `~/.cache/claude-statusline/<session id>.json` (files older than 8 days are deleted). It is an estimate:
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
- Thresholds: edit the `heat` function (colors) and `cache` (cache time colors).
- Priority: edit `$steps` (what grows or appears first) and `$order` (order on the line).

## License

MIT
