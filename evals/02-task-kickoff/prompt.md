---
max_turns: 12
timeout_seconds: 420
allowed_tools: [Skill, "Bash(bash:*)"]
runs: 3
---
Policy: before starting any non-trivial task, check remaining usage capacity against my subscription limits and report it.

Task: plan a 5-step migration of an Express.js service to Fastify. Give me the plan, and tell me whether there is enough capacity to start it now or whether we should wait.
