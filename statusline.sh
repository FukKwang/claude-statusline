#!/bin/bash
export LC_ALL=C.UTF-8  # so ${#var} counts characters, not bytes
# Claude Code status line: model, plan limits with bars, session tokens (main + subagents), context left.
# Bar colors by how full: green < 50, amber < 80, red >= 80.
input=$(cat)
# Last API usage from transcript: cache read/write split and 5m vs 1h TTL.
transcript=$(jq -r '.transcript_path // empty' <<<"$input")
last=$( [ -f "$transcript" ] && tail -n 200 "$transcript" | grep '"usage"' | tail -n 1 | jq -c '.' 2>/dev/null)
# Session tokens (input + cache write + cache read + output), each API call counted once,
# grouped by model family: {"opus": n, "sonnet": n, ...}.
# Main thread from the transcript; subagents (nested too) from <session>/subagents/agent-*.jsonl.
tokens() {
  grep -h '"usage"' "$@" 2>/dev/null | jq -cnR '[inputs | fromjson? | select(.type == "assistant" and .message.usage != null
      and .message.model != "<synthetic>")]
    | unique_by(.message.id) | map({
        family: (.message.model | (capture("(?<f>fable|opus|sonnet|haiku)").f) // .),
        n: (.message.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0)
          + (.cache_read_input_tokens // 0) + (.output_tokens // 0))})
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

# Terminal width: statusline has no tty of its own, so read the parent's.
tty=$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ')
width=$( { stty size <"/dev/$tty" || stty size </dev/tty; } 2>/dev/null | cut -d' ' -f2)
width=$(( ${width:-${COLUMNS:-80}} - 4 ))  # margin for Claude Code padding
paragraph_cols=65  # panes this wide or narrower always get the paragraph

# Layouts, most detailed first; print the first one whose lines all fit the width:
#   0. wide: as 1 or 2, plus the quiet items (bars, context, cache, main/sub tokens per model)
#      all the time
#   1. account and session on one line   2. account line + session line
#   3. as 2, without the per-model split   4. as 3, without the model name
#   5. one compact line   6. a word-wrapped paragraph (always used up to $paragraph_cols columns)
# Quiet items appear only when they need attention: context below 30% left, cache about to
# expire or a low hit rate, limit bars from 50% used.
jq -r --argjson width "$width" --argjson paragraph_cols "$paragraph_cols" --argjson last "${last:-null}" --argjson state "${state:-null}" \
  --argjson main "${main:-{\}}" --argjson sub "${sub:-{\}}" '
  def c($code): "\u001b[\($code)m";
  def r: c("0");
  def dim: c("38;5;240");
  def heat: if . >= 80 then c("1;38;5;203") elif . >= 50 then c("38;5;136") else c("38;5;114") end;
  def bar: (. / 25 | round) as $n | heat + ("▰" * $n) + dim + ("▱" * (4 - $n)) + r;
  def k: if . >= 1000000 then (. / 100000 | floor / 10 | tostring | if test("\\.") then . else . + ".0" end) + "M" elif . >= 1000 then "\(. / 1000 | floor)k" else tostring end;
  def epoch: if type == "string" then sub("\\.[0-9]+"; "") | fromdateiso8601 else . end;
  # Two units at most: 2d 13h, 2h 58m, 58m. A no-break space keeps them together when wrapping.
  def dur: if . >= 86400 then "\(. / 86400 | floor)d\u00a0\(. % 86400 / 3600 | floor)h"
    elif . >= 3600 then "\(. / 3600 | floor)h\u00a0\(. % 3600 / 60 | floor)m" else "\(. / 60 | floor)m" end;
  # " resets in 2h 58m" from a limit window; $sep goes before it.
  # " ↻ 14:32", or " ↻ Wed 19:00" when more than a day away (local time).
  def resets_at: if .resets_at then
    (try ((.resets_at | epoch) as $t | if $t <= now then "" else
      " \(dim)↻\(r) \($t | if . - now > 86400 then strflocaltime("%a %H:%M") else strflocaltime("%H:%M") end)" end)
    catch "") else "" end;
  def resets($sep): if .resets_at then
    (try ((.resets_at | epoch) - now | if . > 0 then "\(dim)\($sep)resets in\(r) \(dur)" else "" end) catch "") else "" end;
  def visible: gsub("\u001b\\[[0-9;]*m"; "") | length;
  def total: [.[]] | add // 0;
  # One-column letters, so the width count stays right.
  def model_icon: {fable: c("1;38;5;213") + "F", opus: c("1;38;5;166") + "O",
    sonnet: c("1;38;5;117") + "S", haiku: c("1;38;5;114") + "H"}[.] // (dim + .);
  # "S32.6M H98k": per model, largest first.
  def models: to_entries | sort_by(-.value) | map("\(.key | model_icon)\(r)\(.value | k)") | join(" ");

  # "5h ▰▰▱▱ 54% +9 resets in 2h 58m": used %, this session (see state above), time to reset.
  def limit($label; $w; $o; $full):
    if $w.used_percentage == null then empty else $w.used_percentage as $u
    | "\(dim)\($label)\(r) "
      + (if $full == "wide" or ($full and $u >= 50) then "\($u | bar) " else "" end)
      + "\($u | heat)\($u | floor)%\(r)"
      + (if $o == null then "" else " \(c("1;38;5;130"))+\([$o.last - $o.base, 0] | max | floor)\(r)" end)
      + (if $full then $w | resets_at else "" end)
    end;

  # Narrow panes: the same facts as a paragraph, word-wrapped to the width.
  # Only single words are colored, so no color runs across a line break.
  # Numbers are bold and darker: usage % by level (dark green, gold, dark red), the rest dark blue.
  def strong: if . >= 80 then c("1;38;5;160") elif . >= 50 then c("1;38;5;136") else c("1;38;5;28") end;
  def pct: "\(strong)\(floor)%\(r)";
  def num: "\(c("1;38;5;25"))\(.)\(r)";
  def plain: gsub("\u001b\\[[0-9;]*m"; "");
  def mine($o): if $o == null then null else [$o.last - $o.base, 0] | max | "\(floor)%" | num end;
  # "2h 58m" until a limit window resets, or null.
  def time_left: try ((.resets_at | epoch) - now | if . > 0 then dur else null end) catch null;
  def wrap($w): split(" ") | reduce .[] as $word ({lines: [], cur: ""};
      if .cur == "" then .cur = $word
      elif (.cur + " " + $word | visible) <= $w then .cur += " " + $word
      else .lines += [.cur] | .cur = $word end)
    | .lines + [.cur];

  # Cache: only when it expires within 2 minutes, has expired, or the last hit rate was below 80%.
  def cache:
    $last.message.usage as $u
    | if $u == null then empty else
      (($u.cache_read_input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.input_tokens // 0)) as $all
      | (if $all > 0 then ($u.cache_read_input_tokens // 0) * 100 / $all else 100 end) as $hit
      | (if ($u.cache_creation.ephemeral_1h_input_tokens // 0) > 0 then 3600 else 300 end) as $ttl
      | (($last.timestamp | epoch) + $ttl - now) as $left
      | [ (if $left <= 0 then "\(c("1;38;5;203"))expired\(r)"
           elif $left < 120 then "\(c("38;5;136"))\(if $left < 60 then "<1m" else "1m" end) left\(r)" else empty end),
          (if $hit < 80 then "\(100 - $hit | heat)hit \($hit | floor)%\(r)" else empty end) ]
      | if . == [] then empty else "\(c("38;5;80"))⛁ cache\(r) " + join(" ") end
      end;

  def cache_sentences:
    $last.message.usage as $u
    | if $u == null then empty else
      (($u.cache_read_input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.input_tokens // 0)) as $all
      | (if $all > 0 then ($u.cache_read_input_tokens // 0) * 100 / $all else 100 end) as $hit
      | (if ($u.cache_creation.ephemeral_1h_input_tokens // 0) > 0 then 3600 else 300 end) as $ttl
      | (($last.timestamp | epoch) + $ttl - now) as $left
      | (if $left <= 0 then "The cache has \(c("1;38;5;160"))expired.\(r)"
         elif $left < 120 then "The cache expires in \(c("1;38;5;136"))\(if $left < 60 then "<1m" else "1m" end)\(r)." else empty end),
        (if $hit < 80 then "The last cache hit rate was \(100 - $hit | strong)\($hit | floor)%\(r)." else empty end)
      end;

  # Wide panes show the quiet items all the time: "⛁ cache 99% hit 4m left".
  def cache_full:
    $last.message.usage as $u
    | if $u == null then empty else
      (($u.cache_read_input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.input_tokens // 0)) as $all
      | (if $all > 0 then ($u.cache_read_input_tokens // 0) * 100 / $all else 100 end) as $hit
      | (if ($u.cache_creation.ephemeral_1h_input_tokens // 0) > 0 then 3600 else 300 end) as $ttl
      | (($last.timestamp | epoch) + $ttl - now) as $left
      | "\(c("38;5;80"))⛁ cache\(r) \(100 - $hit | heat)\($hit | floor)%\(r) \(dim)hit ·\(r) "
        + (if $left <= 0 then "\(c("1;38;5;203"))expired\(r)"
           else "\(if $left < 120 then c("38;5;136") else "" end)\(if $left < 60 then "<1m" else ($left | dur) end)\(r) \(dim)left\(r)" end)
      end;

  .rate_limits.five_hour as $h
  | .rate_limits.seven_day as $w
  | .context_window.remaining_percentage as $left
  | ($main | total) as $m | ($sub | total) as $s
  | ([$main, $sub] | map(to_entries) | add | group_by(.key)
    | map({key: .[0].key, value: (map(.value) | add)}) | from_entries) as $all
  | (if .cost.total_cost_usd then "\(c("1;38;5;150"))$\(.cost.total_cost_usd * 100 | round / 100 | tostring
      | if test("\\.") then (. + "0" | match("^[0-9]+\\.[0-9]{2}").string) else . + ".00" end)\(r)" else null end) as $cost
  | (if $left != null and $left < 30 then "\(100 - $left | heat)◐ \($left | floor)% left\(r)" else null end) as $ctx
  | [try cache catch empty] as $alerts
  | [try cache_sentences catch empty] as $cache_sentences
  | "\(dim)tok\(r) \(c("1"))\($m + $s | k)\(r)" as $tok
  # "main 7.1M (O7.1M) + sub 32.7M (S32.6M H98k) = 39.8M", or "9.0M (O9.0M)" without subagents.
  | (if $s > 0 then
      "\(dim)tok main\(r) \($m | k) \(dim)(\(r)\($main | models)\(dim)) + sub\(r) \($s | k) \(dim)(\(r)\($sub | models)\(dim)) =\(r) \(c("1"))\($m + $s | k)\(r)"
     else "\($tok) \(dim)(\(r)\($all | models)\(dim))\(r)" end) as $tok_wide

  | (if $left == null then null
     else "\(c("38;5;136"))◐\(r) \(dim)ctx\(r) \(100 - $left | bar) \(100 - $left | heat)\($left | floor)%\(r) \(dim)left\(r)" end) as $ctx_full
  | ["\(c("38;5;166"))✻ \(.model.display_name // "Claude")\(r)",
     limit("5h"; $h; $state.five_hour; "wide"), limit("wk"; $w; $state.seven_day; "wide")] as $account_wide
  | ([$ctx_full] + [$cost] + [$tok_wide] + [try cache_full catch empty]) as $session_wide
  | ["\(c("38;5;166"))✻ \(.model.display_name // "Claude")\(r)",
     limit("5h"; $h; $state.five_hour; true), limit("wk"; $w; $state.seven_day; true)] as $account
  | ([$ctx] + [$cost] + [$tok_wide] + $alerts) as $session
  | ([limit("5h"; $h; $state.five_hour; false), limit("wk"; $w; $state.seven_day; false)]
     + [$ctx] + [$cost] + [$tok] + $alerts) as $compact
  | ([$ctx] + [$cost] + [$tok] + $alerts) as $session_short
  | [[$account_wide + $session_wide], [$account_wide, $session_wide], [$account + $session], [$account, $session], [$account, $session_short],
     [$account[1:], $session_short], [$compact],
     ([(if $h.used_percentage == null then empty else
          "You\u0027ve used \($h.used_percentage | pct) of your 5-hour limit"
          + (mine($state.five_hour) | if . then " (\(.) in this chat)" else "" end)
          + ($h | time_left | if . then "; it resets in \(num)." else "." end) end),
        (if $w.used_percentage == null then empty else
          "The week is at \($w.used_percentage | pct)"
          + (mine($state.seven_day) | if . then " (\(.) here)" else "" end)
          + ($w | time_left | if . then " and resets in \(num)." else "." end) end),
        "This chat " + (if $cost then "cost \($cost | plain | num) for" else "used" end) + " \($m + $s | k | num) tokens"
          + (if $s > 0 then " (\($m | k | num) here, \($s | k | num) by subagents)." else "." end),
        (if $left != null and $left < 30 then "Context is down to \(100 - $left | strong)\($left | floor)%\(r)." else empty end),
        $cache_sentences[]]
      | join(" ") | wrap($width) | map([.]))]
  | map(map(map(select(. != null)) | join("   "))) as $layouts
  | if $width + 4 <= $paragraph_cols then $layouts[-1]
    else ($layouts | map(select(map(visible) | max <= $width)) | first) // $layouts[-1] end
  | .[]
' <<<"$input"
