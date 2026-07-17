---
description: Control the Pomodoro timer (start, pause, reset, stop, setup)
allowed-tools: Bash
---

!`"${CLAUDE_PLUGIN_ROOT}/scripts/pomodoro" -$ARGUMENTS`

Confirm in one sentence that the Pomodoro timer performed the «$ARGUMENTS» action. If the output above shows an error (e.g. a usage message), list the valid actions instead: start, pause, reset, stop, and setup <work mm:ss> <break mm:ss> (e.g. setup 50:00 10:00).
