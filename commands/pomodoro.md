---
description: Control the Pomodoro timer (start, pause, reset, stop, setup)
allowed-tools: Bash
---

!`"${CLAUDE_PLUGIN_ROOT}/scripts/pomodoro" -$ARGUMENTS`

Confirm in one sentence that the Pomodoro timer performed the «$ARGUMENTS» action. If the output above shows an error (e.g. a usage message), output exactly this sentence instead: «Valid calls: /pomodoro start, /pomodoro pause, /pomodoro reset, /pomodoro stop, /pomodoro setup <work mm:ss> <break mm:ss>.»
