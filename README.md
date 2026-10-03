# claude-statusline

A colorful status line for [Claude Code](https://claude.com/claude-code). It shows your plan limits, context, cost and tokens at a glance.

```
✻ Opus 5.5  │  ◷ 5h ▰▰▱▱▱▱▱▱ 23% ↻ 2h12m  │  ◈ wk ▰▰▰▰▰▱▱▱ 67% ↻ 3d11h19m  │  ◐ ctx ▰▰▰▰▰▰▰▱ 12% left  │  💰 $12.35 · 1.5M tok
```

## What it shows

| Segment | Meaning |
|---------|---------|
| `✻ Opus 5.5` | Current model |
| `◷ 5h` | 5-hour session limit used, and time until it resets |
| `◈ wk` | Weekly limit used, and time until it resets |
| `◐ ctx` | Context window used (bar) and remaining (number) |
| `💰` | Session cost in USD and total tokens (input + output) |

Bars turn green, then amber at 50%, then red at 80%.

The line wraps by segment when your terminal is narrow, so nothing gets cut off.

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
  "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }
}
```

The status line appears after your next message.

## Customize

- Colors: edit the `38;5;N` codes (256-color palette) in `statusline.sh`.
- Thresholds: edit the `heat` function.

## License

MIT
