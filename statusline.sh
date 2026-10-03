#!/bin/bash
export LC_ALL=C.UTF-8  # so ${#var} counts characters, not bytes
# Claude Code status line: model, plan limits with bars, session tokens, context left.
# Bar colors by how full: green < 50, amber < 80, red >= 80.
segments=$(jq -r '
  def c($code): "\u001b[\($code)m";
  def r: c("0");
  def dim: c("38;5;240");
  def heat: if . >= 80 then c("1;38;5;203") elif . >= 50 then c("38;5;221") else c("38;5;114") end;
  def bar($full): ($full / 12.5 | round) as $n
    | ($full | heat) + ("▰" * $n) + dim + ("▱" * (8 - $n)) + r;
  def meter($icon; $label; $shown; $full):
    if $shown == null then "\($icon) \(dim)\($label) ▱▱▱▱▱▱▱▱ --\(r)"
    else "\($icon) \(c("1"))\($label)\(r) \(bar($full)) \($full | heat)\($shown | floor)%\(r)" end;
  def k: if . >= 1000000 then "\(. / 100000 | floor / 10)M" elif . >= 1000 then "\(. / 1000 | floor)k" else tostring end;
  def until($t): (if ($t | type) == "string" then ($t | sub("\\.[0-9]+"; "") | fromdateiso8601) else $t end) - now
    | if . <= 0 then "" else " \(dim)↻ \(if . >= 86400 then "\(. / 86400 | floor)d" else "" end)\(. % 86400 / 3600 | floor)h\(. % 3600 / 60 | floor)m\(r)" end;
  .rate_limits.five_hour as $h
  | .rate_limits.seven_day as $w
  | .context_window.remaining_percentage as $left
  | ("\(c("38;5;209"))✻ \(.model.display_name // "Claude")\(r)"),
  (meter("\(c("38;5;117"))◷\(r)"; "5h"; $h.used_percentage; $h.used_percentage)
    + (if $h.resets_at then (try until($h.resets_at) catch "") else "" end)),
  (meter("\(c("38;5;183"))◈\(r)"; "wk"; $w.used_percentage; $w.used_percentage)
    + (if $w.resets_at then (try until($w.resets_at) catch "") else "" end)),
  (meter("\(c("38;5;222"))◐\(r)"; "ctx"; $left; if $left == null then 0 else 100 - $left end)
    + (if $left == null then "" else " \(dim)left\(r)" end)),
  ("\(c("38;5;150"))💰\(r) \(if .cost.total_cost_usd then "\(c("1;38;5;150"))$\(.cost.total_cost_usd * 100 | round / 100 | tostring | if test("\\.") then (. + "0" | match("^[0-9]+\\.[0-9]{2}").string) else . + ".00" end)\(r) \(dim)·\(r) " else "" end)\(c("1"))\(((.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)) | k)\(r) \(dim)tok\(r)")
')

# Terminal width: statusline has no tty of its own, so read the parent's.
tty=$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ')
width=$( { stty size <"/dev/$tty" || stty size </dev/tty; } 2>/dev/null | cut -d' ' -f2)
width=$(( ${width:-${COLUMNS:-80}} - 4 ))  # margin for Claude Code padding

# Pack segments greedily into lines that fit; visible length ignores ANSI codes.
sep=$'  \e[38;5;240m│\e[0m  '
line='' len=0
while IFS= read -r seg; do
  plain=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$seg")
  n=$(( ${#plain} + 1 ))  # +1: 💰 renders 2 columns wide
  if (( len > 0 && len + 5 + n > width )); then
    printf '%s\n' "$line"; line='' len=0
  fi
  if (( len > 0 )); then line+=$sep; len=$(( len + 5 )); fi
  line+=$seg; len=$(( len + n ))
done <<<"$segments"
printf '%s\n' "$line"
