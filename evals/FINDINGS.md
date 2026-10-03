# Findings from eval setup — 2026-10-03

Things surfaced while building the eval suite that need a decision or a fix.
The eval suite tests the plugin as it is today; none of these were changed during setup.

Evidence sources: three pilot runs (`evals/results/2026-10-03T06-*`), the user's Claude Code
transcripts under `~/.claude/projects`, and manual reproduction of the script outside the eval.

---

## A. Plugin fixes (script and SKILL.md)

### A1. The script fails silently when the nested `claude -p "/usage"` call fails
**Severity: high.** In every live eval run the script produced no output at all: no usage lines, no
error, exit 0 as far as the caller could tell. Cause: `set -euo pipefail` plus
`output="$(claude -p "/usage" 2>&1)"`. If the nested `claude` exits non-zero the script dies at that
line before printing anything. The agent then reports "the script printed nothing" and cannot
diagnose further.

Reproduced outside the eval: with an isolated config dir (`CLAUDE_CONFIG_DIR` pointing at an empty
directory, or an empty `HOME`), `claude -p "/usage"` prints the generic cost summary block
(`Total cost: $0.0000 ... Usage: 0 input, 0 output ...`) instead of usage lines. That path does hit
the script's fallback branch and prints the raw block. The fully silent case happens inside the eval
sandbox, where the nested call appears to fail outright.

**Suggested fix:** capture the exit code explicitly, print stderr, and emit a clear one-line message
such as `check-usage: could not reach /usage (exit N): <stderr>` so the caller can tell "not
authenticated / not reachable" from "API-key billing" from "format changed".

### A2. The third output line (`Current week (Fable)`) is undocumented
**Severity: low.** The live script now prints three lines: session, week (all models), week (Fable).
README and SKILL.md both show only two. The WARNING logic correctly keys on `(all models)` only, but
SKILL.md should tell the agent whether to relay the per-model line or ignore it.

### A3. SKILL.md guidance only engages when the script is run
**Severity: medium.** The WARNING-first rule, the credits/grace-window explanation, and the
`/usage-credits` pointer live in SKILL.md, and SKILL.md is only loaded when the skill fires. When a
user pastes `/usage` output and asks "continue or pause?", the skill does not fire (observed in all
pilot runs for pasted-number prompts). The model then answers from its own judgement. In pilot 3,
case `03-week-exhausted`, both arms said "you'll be rate-limited no matter how much session room is
left", which is the exact misconception the WARNING section was written to correct (requests may
keep succeeding on paid credits).

**Options:** extend the description so the skill also triggers on "interpret this /usage output"
style prompts; or move the interpretation rules into a place that applies regardless (e.g. CLAUDE.md
policy). Until then, eval case 03 will stay at zero delta.

### A4. The WARNING branch cannot be exercised on demand
**Severity: medium (testability).** The script reads the live account, so whether the WARNING fires
depends on the real weekly percentage. There is no way to test it deterministically. A plugin-side
hook such as `CHECK_USAGE_INPUT_FILE=<path>` (read canned `/usage` output instead of calling
`claude -p`) would let the eval cover the WARNING branch, the credits line, and the API-key fallback
end to end instead of via pasted text.

---

## B. Triggering and real-world behaviour (from transcripts)

### B1. The skill under-fires relative to how the user wants it used
Across all transcripts:

| route | count |
|---|---|
| Invoked through the Skill tool | 38 |
| Script run directly via Bash (no Skill call) | ~198 |

Almost every Skill invocation was driven by the CLAUDE.md "before any non-trivial task" policy, not
by the skill's own description. Preceding user prompts were task kickoffs (tackle the next batch of items, review an error,
plain "continue"), not questions about usage. The description
("Use when the user asks about usage limits…") does not mention step boundaries, task kickoff, or
resume-after-reset, which is where the user actually wants it. Consider adding those triggers to the
description.

### B2. Observed failures in real sessions (before and after the WARNING was added)
Three patterns, each seen at least once in the transcript review (details paraphrased):
- Weekly at 100% with the session near 0%: Claude treated the session headroom as sufficient and
  carried on, flagging the weekly ceiling only as a future risk. This is the failure the WARNING now
  targets.
- Weekly at 97%: Claude noted the figure and continued, with no mention of what happens past 100%.
- Session at ~90%, weekly at ~91%: the reply did not mention usage at all and continued working.

The ~90% pause threshold lives in CLAUDE.md, not in the skill. Decide whether SKILL.md should state
a recommended decision rule or leave that to policy; today the skill reports numbers and the policy
decides, and B2 shows the policy step being skipped.

### B3. Direct Bash runs bypass SKILL.md
Because the script is usually run directly (B1), the guidance in SKILL.md is often not in context
when the numbers come back. That compounds A3. Putting the critical interpretation rule (weekly
exhausted ⇒ flag credits) into the script's own output text, as the WARNING already does, is the
robust path; anything that only lives in SKILL.md will be missed on direct runs.

---

## C. Eval suite limitations (known, accepted)

### C1. The sandbox cannot reach the real account
The eval runner gives the agent an isolated config dir with no credentials. The nested `/usage`
call therefore never returns usage lines, so the live path is untestable here. Cases 01 and 02
measure "attempts the check and reports honestly" rather than "reports correct numbers". There is no
runner flag to pass auth through, and copying credentials into the sandbox is not an acceptable
workaround. A4 is the proper fix.

### C2. Only two cases carry measurable delta today
Pilot 3 (1 run, both arms): 01 Δ +0.67, 02 Δ +0.40, all others Δ 0. Cases 03 and 04 pass or fail
identically in both arms because the skill does not fire on pasted numbers (A3). The negatives are
expected to be Δ 0.

### C3. Judge reasoning is not stored
`aggregate-result.json` records judge votes only (e.g. `FAIL FAIL FAIL`), not the rationale. To
debug a surprising grade, re-run with `--keep-temp` and read the trace, or reason from the reply
against the rubric as was done here.

### C4. Bash permission pattern does not cover compound commands
`--allow-tools "Bash(bash:*)"` permits `bash <script>` but denied the agent's retry
`bash <script> 2>&1; echo "exit=$?"`. Harmless for scoring, but it is why the agent could not
self-diagnose A1 inside the sandbox.

### C5. Negatives are the expensive cases
Cases 05 and 06 cost ≈ $1 each per arm-pair because the model spends five turns looking for docs
before answering. Lowering their `max_turns` to 3 would roughly halve suite cost with no loss of
signal, since the graders only need the final answer.

### C6. Open question: timezone of reset times in cloud sessions
The user wanted to see whether cloud sessions report reset times in UTC or the machine's local time.
Not observable here because the script returns nothing in the sandbox (C1).

---

## D. Housekeeping

- **`evals/results/` is untracked.** Add it to `.gitignore` before committing the suite, or decide
  to keep pilot reports in the repo.
- **Repo layout is not a standard plugin layout.** No `.claude-plugin/plugin.json`, no `skills/`
  dir; SKILL.md sits at the root and is installed by symlink. The eval runner loaded it anyway
  (`suite.plugins` listed it with no problem code), so this is cosmetic for now.
- **Full-run command and cost** (from `evals/` setup): about $10 per full run at `runs: 3`.

  ```
  claude plugin eval . --ablation with-without --judge-model sonnet --allow-tools "Bash(bash:*)"
  ```
