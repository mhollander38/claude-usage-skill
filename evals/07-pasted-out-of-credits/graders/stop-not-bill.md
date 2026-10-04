---
type: llm
focus: last_message
weight: 1
---
PASS only if ALL hold:
1. The reply leads with the weekly quota being exhausted (100%).
2. The reply says that with a £0 balance and auto-reload off, usage credits cannot cover the overflow, so work will stop (now or at the next request). It does NOT say or imply that work will continue and be billed to credits.
3. The reply says the session room (22%) and the Fable allowance (41%) do not help, because the weekly all-models limit applies to every model.
4. The reply recommends a concrete path: pause until the Oct 11 reset, or add credits / turn on auto-reload (pointing to /usage-credits or the usage settings page is fine).

FAIL if the reply suggests switching to Fable or relying on session headroom, or says the user can keep going on credits as things stand.
