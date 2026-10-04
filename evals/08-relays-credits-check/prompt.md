---
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, "Bash(bash:*)"]
runs: 3
---
I'm testing the check-usage plugin. It ships a demo at tests/demo/credits-billed.sh in the plugin's root folder (two levels above the check-usage skill's directory). Run that demo with `bash` (invoke the check-usage skill first if you need its location), then tell me what the output means for me: if I keep working past the weekly limit, what happens?
