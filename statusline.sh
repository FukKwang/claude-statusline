#!/bin/bash
export LC_ALL=C.UTF-8  # so ${#var} counts characters, not bytes
# Claude Code status line: model, plan limits with bars, session tokens (main + subagents), context left,
# background /implement-long runs.
# Bar colors by how full: green < 50, amber < 80, red >= 80.
input=$(cat)
# Last API usage from transcript: cache read/write split and 5m vs 1h TTL.
transcript=$(jq -r '.transcript_path // empty' <<<"$input")
last=$( [ -f "$transcript" ] && tail -n 200 "$transcript" | grep '"usage"' | tail -n 1 | jq -c '.' 2>/dev/null)
# Session tokens (input + cache write + output), each API call counted once. Cache reads are
# left out: every call re-reads the whole context, so they would count it again each turn.
# Grouped by model family: {"opus": n, "sonnet": n, ...}.
# Main thread from the transcript; subagents (nested too) from <session>/subagents/agent-*.jsonl.
tokens() {
  grep -h '"usage"' "$@" 2>/dev/null | jq -cnR '[inputs | fromjson? | select(.type == "assistant" and .message.usage != null
      and .message.model != "<synthetic>")]
    | unique_by(.message.id) | map({
        family: (.message.model | (capture("(?<f>fable|opus|sonnet|haiku)").f) // .),
        n: (.message.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0)
          + (.output_tokens // 0))})
    | group_by(.family) | map({key: .[0].family, value: (map(.n) | add)}) | from_entries'
}
main='{}' sub='{}'
if [ -f "$transcript" ]; then
  main=$(tokens "$transcript")
  subs=("${transcript%.jsonl}"/subagents/agent-*.jsonl)
  [ -f "${subs[0]}" ] && sub=$(tokens "${subs[@]}")
fi

# This session's share of the current 5h and weekly windows: remember the used % when the
# session first sees each window, then show how much it went up. A new window counts from 0.
state_dir=${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline
sid=$(jq -r '.session_id // empty' <<<"$input")
state=null
if [ -n "$sid" ] && mkdir -p "$state_dir" 2>/dev/null; then
  f="$state_dir/$sid.json"
  state=$(jq -c --argjson old "$(cat "$f" 2>/dev/null || echo null)" '
    def track($w; $o): $w.used_percentage as $u
      | if $u == null or ($w.resets_at | type) != "number" then $o
        elif $o == null then {resets_at: $w.resets_at, base: $u, last: $u}
        elif $w.resets_at > $o.resets_at + 600 then {resets_at: $w.resets_at, base: 0, last: $u}
        else $o + {last: $u} end;
    {five_hour: track(.rate_limits.five_hour; $old.five_hour),
     seven_day: track(.rate_limits.seven_day; $old.seven_day)}' <<<"$input" 2>/dev/null) || state=null
  [ -n "$state" ] && [ "$state" != null ] && printf '%s' "$state" >"$f.$$" && mv "$f.$$" "$f"
  find "$state_dir" -name '*.json' -mtime +8 -delete 2>/dev/null
fi

# Background /implement-long runs (software-factory): the latest one still running.
# Read through implement-long-stats.py in the project's .claude/, else in ~/.claude/.
runs='[]'
proj=$(jq -r '.workspace.project_dir // .cwd // empty' <<<"$input")
for d in "$proj/.claude" "$HOME/.claude"; do
  if [ -f "$d/tools/implement-long-stats.py" ] && compgen -G "$d/runs/*.json" >/dev/null; then
    runs=$(python3 -I "$d/tools/implement-long-stats.py" status 2>/dev/null) || runs='[]'
    break
  fi
done

# Terminal width: statusline has no tty of its own, so read the parent's.
tty=$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ')
width=$( { stty size <"/dev/$tty" || stty size </dev/tty; } 2>/dev/null | cut -d' ' -f2)
width=$(( ${width:-${COLUMNS:-80}} - 4 ))  # margin for Claude Code padding

# Every item has forms from short to long. The four core items (context left, cache time
# left, tokens, this session's share of the 5h limit) always show, in their short form; they
# wrap onto more lines only in very narrow panes. Then, in order of importance, items grow
# or appear while everything still fits in the lines the core items need (see "steps").
jq -r --argjson width "$width" --argjson last "${last:-null}" --argjson state "${state:-null}" \
  --argjson main "${main:-{\}}" --argjson sub "${sub:-{\}}" --argjson runs "${runs:-[]}" '
  def c($code): "\u001b[\($code)m";
  def r: c("0");
  def dim: c("38;5;240");
  def bold: c("1");
  def heat: if . >= 80 then c("1;38;5;203") elif . >= 50 then c("38;5;136") else c("38;5;114") end;
  def bar: (. / 25 | round) as $n | heat + ("▰" * $n) + dim + ("▱" * (4 - $n)) + r;
  def k: if . >= 1000000 then (. / 100000 | floor / 10 | tostring | if test("\\.") then . else . + ".0" end) + "M" elif . >= 1000 then "\(. / 1000 | floor)k" else tostring end;
  def epoch: if type == "string" then sub("\\.[0-9]+"; "") | fromdateiso8601 else . end;
  # Two units at most: 2d 13h, 2h 58m, 58m. A no-break space keeps them together.
  def dur: if . >= 86400 then "\(. / 86400 | floor)d \(. % 86400 / 3600 | floor)h"
    elif . >= 3600 then "\(. / 3600 | floor)h \(. % 3600 / 60 | floor)m" else "\(. / 60 | floor)m" end;
  # " ↻ 14:32", or " ↻ Wed 19:00" when more than a day away (local time).
  def resets_at: if .resets_at then
    (try ((.resets_at | epoch) as $t | if $t <= now then "" else
      " \(dim)↻\(r) \($t | if . - now > 86400 then strflocaltime("%a %H:%M") else strflocaltime("%H:%M") end)" end)
    catch "") else "" end;
  def visible: gsub("\u001b\\[[0-9;]*m"; "") | length;
  def total: [.[]] | add // 0;
  # One-column letters, so the width count stays right.
  def model_icon: {fable: (c("1;38;5;213") + "F"), opus: (c("1;38;5;166") + "O"),
    sonnet: (c("1;38;5;117") + "S"), haiku: (c("1;38;5;114") + "H")}[.] // (dim + .);
  # "S 1.1M, H 9k": per model, largest first.
  def models: to_entries | sort_by(-.value) | map("\(.key | model_icon)\(r) \(.value | k)") | join(", ");
  def usd: "$\(. * 100 | round / 100 | tostring
    | if test("\\.") then (. + "0" | match("^[0-9]+\\.[0-9]{2}").string) else . + ".00" end)";

  # /implement-long runs: "⚙ sheet-view 12m", "⚙ impl sheet-view 12m · Σ 1.2M · ctx 84k · $0.84".
  # Only the most recently started run that is still running; finished runs are hidden.
  def run_forms: ($runs | map(select(.status == "running")) | sort_by(.elapsed_s) | .[:1]) as $runs
    | if $runs == [] then [""] else
    ($runs | map(
      ({running: (c("1;38;5;136") + "⚙"), done: (c("1;38;5;114") + "✓")}[.status] // (c("1;38;5;203") + "✗")) as $icon
      | (.name | if length > 18 then .[:17] + "…" else . end) as $name
      | ["\($icon)\(r) \($name) \(.elapsed_s | dur)",
         "\($icon)\(r) \(dim)impl\(r) \($name) \(.elapsed_s | dur)"
         + (if .tokens > 0 then " \(dim)·\(r) \(c("38;5;141"))Σ\(r) \(.tokens | k)" else "" end)
         + (if .ctx then " \(dim)· ctx\(r) \(.ctx | k)" else "" end)
         + (if .cost_usd then " \(dim)·\(r) \(c("1;38;5;150"))\(.cost_usd | usd)\(r)" else "" end)
         + (if .status == "running" or .status == "done" then "" else " \(c("1;38;5;203"))\(.status)\(r)" end)])) as $each
    | [($each | map(.[0]) | join("  ")), ($each | map(.[1]) | join("  "))] end;

  # Limit forms: "5h +9%" (this session), "5h 54% +9%", with bar, with reset time.
  # $core: the short form shows the share of this session; otherwise the item starts hidden.
  def limit($label; $w; $o; $core):
    if $w.used_percentage == null then [""] else $w.used_percentage as $u
    | (if $o == null then null else " \(c("1;38;5;130"))+\([$o.last - $o.base, 0] | max | floor)%\(r)" end) as $mine
    | "\(dim)\($label)\(r) " as $l
    | "\($u | heat)\($u | floor)%\(r)" as $pct
    | [(if $core then $l + ($mine // (" " + $pct) | ltrimstr(" ")) else "" end),
       $l + $pct + ($mine // ""),
       $l + "\($u | bar) " + $pct + ($mine // ""),
       $l + "\($u | bar) " + $pct + ($mine // "") + ($w | resets_at)]
    end;

  # Cache forms: "⛁ 4m", "⛁ cache 4m", "⛁ cache 4m · 99% hit".
  def cache:
    $last.message.usage as $u
    | if $u == null then [""] else
      (($u.cache_read_input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.input_tokens // 0)) as $all
      | (if $all > 0 then ($u.cache_read_input_tokens // 0) * 100 / $all else 100 end) as $hit
      | (if ($u.cache_creation.ephemeral_1h_input_tokens // 0) > 0 then 3600 else 300 end) as $ttl
      | (($last.timestamp | epoch) + $ttl - now) as $left
      | (if $left <= 0 then "\(c("1;38;5;203"))expired\(r)"
         elif $left < 120 then "\(c("1;38;5;136"))\(if $left < 60 then "<1m" else "1m" end)\(r)"
         else "\(bold)\($left | dur)\(r)" end) as $t
      | "\(c("38;5;80"))⛁\(r)" as $icon
      | ["\($icon) \($t)", "\($icon) \(dim)cache\(r) \($t)",
         "\($icon) \(dim)cache\(r) \($t) \(dim)·\(r) \(100 - $hit | heat)\($hit | floor)%\(r) \(dim)hit\(r)"]
      end;

  # Put items on lines of at most $width columns; an item is never split.
  def pack: reduce .[] as $it ([];
    if . == [] then [$it]
    elif (.[-1] + "   " + $it | visible) <= $width then .[-1] += "   " + $it
    else . + [$it] end);

  .rate_limits.five_hour as $h
  | .rate_limits.seven_day as $w
  | .context_window.remaining_percentage as $left
  | ($main | total) as $m | ($sub | total) as $s
  | ([$main, $sub] | map(to_entries) | add | group_by(.key)
    | map({key: .[0].key, value: (map(.value) | add)}) | from_entries) as $all
  | "\(bold)\($m + $s | k)\(r)" as $total
  | "\(c("38;5;141"))Σ\(r)" as $sigma
  | {
      model: ["", "\(c("38;5;166"))✻ \(.model.display_name // "Claude")\(r)"],
      ctx: (if $left == null then [""] else "\(100 - $left | heat)\($left | floor)%\(r)" as $p
        | "\(c("38;5;136"))◐\(r)" as $icon
        | ["\($icon) \($p)", "\($icon) \(dim)context\(r) \($p)",
           "\($icon) \(dim)context\(r) \(100 - $left | bar) \($p)"] end),
      cache: (try cache catch [""]),
      # "Σ 1.4M", "Σ tokens 1.4M", "Σ tokens main 310k (O 310k) + subagents 1.1M (S 1.1M, H 9k) = 1.4M".
      tok: ["\($sigma) \($total)", "\($sigma) \(dim)tokens\(r) \($total)", (if $s > 0 then
          "\($sigma) \(dim)tokens main\(r) \($m | k) \(dim)(\(r)\($main | models)\(dim)) + subagents\(r) \($s | k) \(dim)(\(r)\($sub | models)\(dim)) =\(r) \($total)"
        elif $all == {} then "\($sigma) \(dim)tokens\(r) \($total)" else "\($sigma) \(dim)tokens\(r) \($total) \(dim)(\(r)\($all | models)\(dim))\(r)" end)],
      "5h": limit("5h"; $h; $state.five_hour; true),
      wk: limit("wk"; $w; $state.seven_day; false),
      cost: ["", (if .cost.total_cost_usd then "\(c("1;38;5;150"))$\(.cost.total_cost_usd * 100 | round / 100 | tostring
        | if test("\\.") then (. + "0" | match("^[0-9]+\\.[0-9]{2}").string) else . + ".00" end)\(r)" else "" end)],
      run: (try run_forms catch [""])
    } as $forms
  # Display order.
  | ["model", "ctx", "cache", "tok", "5h", "wk", "cost", "run"] as $order
  | def render: . as $lv | [$order[] | $forms[.][$lv[.]] | select(. != "")] | pack;
  # Most important first: core items grow before the extras appear.
  [["ctx", 1], ["cache", 1], ["tok", 1], ["5h", 1], ["wk", 1], ["model", 1], ["tok", 2],
   ["run", 1], ["ctx", 2], ["5h", 2], ["wk", 2], ["cost", 1], ["cache", 2], ["5h", 3], ["wk", 3]] as $steps
  | ($order | map({key: ., value: 0}) | from_entries) as $base
  | ($base | render | length) as $lines
  | reduce $steps[] as [$key, $n] ($base;
      (.[$key] = $n) as $try
      | if .[$key] == $n - 1 and ($forms[$key] | length) > $n and ($try | render | length) <= $lines
        then $try else . end)
  | render | .[]
' <<<"$input"
