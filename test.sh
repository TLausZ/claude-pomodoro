#!/usr/bin/env bash
# Full branch coverage of scripts/pomodoro and scripts/pomodoro-segment.
# Runs against a throwaway $HOME; notifications hit stub binaries, never the desktop.
set -e
cd "$(dirname "$0")"
export HOME=$(mktemp -d)
mkdir -p "$HOME/.claude"
STATE="$HOME/.claude/pomodoro-state"
CONF="$HOME/.claude/pomodoro-config"
LAST="$HOME/.claude/pomodoro-lastphase"

fail() { echo "FAIL: $1"; exit 1; }

# ── CLI: scripts/pomodoro ───────────────────────────────────────────────────

# no action / unknown action -> usage, exit 1
! scripts/pomodoro        2>/dev/null || fail "no action should exit 1"
! scripts/pomodoro -bogus 2>/dev/null || fail "unknown action should exit 1"

# -start fresh
scripts/pomodoro -start
read -r mode val < "$STATE"
[ "$mode" = running ] || fail "-start fresh"

# -start while running restarts at now
echo "running 1000" > "$STATE"
scripts/pomodoro -start
read -r mode val < "$STATE"
[ "$mode" = running ] && [ $(( $(date +%s) - val )) -lt 5 ] || fail "-start while running"

# -pause while running freezes elapsed
scripts/pomodoro -pause
read -r mode val < "$STATE"
[ "$mode" = paused ] && [ "$val" -lt 5 ] || fail "-pause"

# -pause while already paused: no-op
cp "$STATE" "$STATE.before"
scripts/pomodoro -pause
cmp -s "$STATE" "$STATE.before" || fail "-pause when paused should be a no-op"

# -start after pause resumes from the paused position
echo "paused 3100" > "$STATE"
scripts/pomodoro -start
read -r mode val < "$STATE"
elapsed=$(( $(date +%s) - val ))
[ "$mode" = running ] && [ "$elapsed" -ge 3100 ] && [ "$elapsed" -lt 3105 ] || fail "resume"

# -reset restarts at 00:00
scripts/pomodoro -reset
read -r mode val < "$STATE"
[ "$mode" = running ] && [ $(( $(date +%s) - val )) -lt 5 ] || fail "-reset"

# -stop removes state; -pause while stopped: no-op, creates nothing
scripts/pomodoro -stop
[ ! -f "$STATE" ] || fail "-stop"
scripts/pomodoro -pause
[ ! -f "$STATE" ] || fail "-pause while stopped should be a no-op"

# -setup valid: confirms and writes config in seconds
out=$(scripts/pomodoro -setup 01:00 00:30)
[ "$out" = "work 01:00, break 00:30" ] || fail "-setup output: $out"
read -r work brk < "$CONF"
[ "$work" = 60 ] && [ "$brk" = 30 ] || fail "-setup config"

# -setup invalid: bad format, seconds > 59, all-zero cycle, missing args
! scripts/pomodoro -setup 50 10       2>/dev/null || fail "-setup 50 10 should fail"
! scripts/pomodoro -setup 50:99 10:00 2>/dev/null || fail "-setup 50:99 should fail"
! scripts/pomodoro -setup 00:00 00:00 2>/dev/null || fail "-setup zero cycle should fail"
! scripts/pomodoro -setup             2>/dev/null || fail "-setup without args should fail"
rm -f "$CONF"

# ── Status line: scripts/pomodoro-segment ───────────────────────────────────

seg() { scripts/pomodoro-segment; }

# stopped -> no output; empty state file -> no output
[ -z "$(seg)" ] || fail "stopped should print nothing"
: > "$STATE"
[ -z "$(seg)" ] || fail "empty state should print nothing"

# defaults (no config): 5 min in = work phase, paused marker, deterministic emoji
echo "paused 300" > "$STATE"
case "$(seg)" in *"05:00 ⏸"*) ;; *) fail "work phase (defaults)";; esac
[ "$(seg)" = "$(seg)" ] || fail "emoji must be stable within a phase"

# defaults: 51:40 = break phase
echo "paused 3100" > "$STATE"
case "$(seg)" in *"51:40 ⏸"*) ;; *) fail "break phase (defaults)";; esac

# paused mode never notifies
[ ! -f "$LAST" ] || fail "paused must not touch lastphase"

# config override: 60 s work / 30 s break, 75 s in = break phase
scripts/pomodoro -setup 01:00 00:30 > /dev/null
echo "paused 75" > "$STATE"
case "$(seg)" in *"01:15 ⏸"*) ;; *) fail "config override";; esac
rm -f "$CONF"

# ── Notifications (stubbed osascript / notify-send) ─────────────────────────
# PATH is narrowed to the stub dir plus /bin (bash, date, cat) so the segment
# script finds the stubs instead of the real notifier.

STUB=$(mktemp -d)
printf '#!/bin/sh\necho osascript "$@" >> "%s/calls"\n'   "$STUB" > "$STUB/osascript"
printf '#!/bin/sh\necho notify-send "$@" >> "%s/calls"\n' "$STUB" > "$STUB/notify-send"
chmod +x "$STUB/osascript" "$STUB/notify-send"

wait_calls() {  # notify runs in the background; poll briefly for the stub log
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$STUB/calls" ] && return 0; sleep 0.1; done
  return 1
}

# running mode, entering work phase: osascript preferred when present
echo "running $(( $(date +%s) - 100 ))" > "$STATE"
out=$(PATH="$STUB:/bin" scripts/pomodoro-segment)
case "$out" in *"01:4"*) ;; *) fail "running work clock: $out";; esac
case "$out" in *"⏸"*) fail "running must not show pause marker";; esac
[ "$(cat "$LAST")" = work ] || fail "lastphase after work transition"
wait_calls || fail "osascript stub not called"
grep -q '^osascript .*Back to work' "$STUB/calls" || fail "osascript work notification"

# same phase again: no second notification
rm -f "$STUB/calls"
out=$(PATH="$STUB:/bin" scripts/pomodoro-segment)
sleep 0.3
[ ! -f "$STUB/calls" ] || fail "no notification without phase change"

# entering break phase without osascript: notify-send fallback
mv "$STUB/osascript" "$STUB/osascript.off"
echo "running $(( $(date +%s) - 3050 ))" > "$STATE"
out=$(PATH="$STUB:/bin" scripts/pomodoro-segment)
case "$out" in *"50:5"*) ;; *) fail "running break clock: $out";; esac
[ "$(cat "$LAST")" = break ] || fail "lastphase after break transition"
wait_calls || fail "notify-send stub not called"
grep -q '^notify-send .*Coffee break' "$STUB/calls" || fail "notify-send break notification"

# phase change with no notifier at all: silent, but lastphase still tracked
rm -f "$LAST" "$STUB/calls"
out=$(PATH=/bin scripts/pomodoro-segment)
[ "$(cat "$LAST")" = break ] || fail "lastphase without notifier"
sleep 0.3
[ ! -f "$STUB/calls" ] || fail "no notifier must stay silent"

echo "all tests passed"
