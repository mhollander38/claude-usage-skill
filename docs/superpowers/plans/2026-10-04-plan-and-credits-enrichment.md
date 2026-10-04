# Plan and Credits Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After the `/usage` lines, print best-effort plan tier, binding limit, usage-credits state and included-credit lines read from Claude Code's local usage cache; make the weekly-exhausted WARNING definitive about bill vs stop; teach SKILL.md that per-model lines are sub-caps; add fixtures and one discriminating eval case.

**Architecture:** A new `skills/check-usage/scripts/usage-cache.py` reads the config JSON (`~/.claude.json` by default), validates freshness and account match, and prints zero or more lines; it never fails loudly. `check-usage.sh` calls it after printing the matched lines, only when python3 is available, and only reads the real cache in live mode (canned mode needs an explicit `CHECK_USAGE_CACHE_FILE`). The text parse stays primary.

**Tech Stack:** bash 3.2, python3 standard library only (optional at runtime: absent python3 ⇒ no enrichment).

**Spec:** `docs/research/2026-10-03-plan-limits-and-credits.md` section 5 (Recommendations 1–6).

## Global Constraints

- bash 3.2 compatible; no `timeout`.
- python3 is optional. If it is missing, or the cache is missing/stale/malformed/mismatched, the script output is exactly what it is today. The enrichment step must never change the exit code and never print a Python traceback.
- Canned mode (`CHECK_USAGE_INPUT_FILE` set) must NOT read the real `~/.claude.json` unless `CHECK_USAGE_CACHE_FILE` is set explicitly. Tests must never read the real cache or call the real CLI.
- Never print raw obfuscated cache key names (e.g. `iguana_necktie`) or any personal field (email, name, UUIDs) in script output.
- Existing output lines, the WARNING's four lines, NOTICE text, `check-usage:` lines and exit codes are unchanged. New lines are appended after a blank line.
- Fixture JSON contains no real personal data: use `00000000-0000-0000-0000-000000000001` style UUIDs.
- Eval floor: new case keeps `runs: 3`, has outcome graders, and the two negative cases remain.
- Commit after every task. Commit messages end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Ub6MrWMjj4X3nxSh8jzwKV`

## Review Focus

1. **Cache from a different account** (`cachedUsageUtilization.accountUuid` ≠ `oauthAccount.accountUuid`): no enrichment at all. Pinned in Task 1.
2. **Stale cache** (older than 180 s, or more than 60 s in the future): no enrichment; WARNING falls back to the either/or wording with no `Credits check:` line. Pinned in Tasks 1 and 2.
3. **python3 missing**: script output identical to no-cache output, exit unchanged. Pinned in Task 2 via `CHECK_USAGE_PYTHON`.
4. **Canned input without `CHECK_USAGE_CACHE_FILE`**: never reads `~/.claude.json`. Pinned in Task 2 (`HOME` pointed at a temp dir holding a valid cache; assert no `Plan:` line).
5. **Malformed or partial JSON** (`{not json`, `utilization` missing, `limits` not a list): no traceback, no output, exit 0 from the helper. Pinned in Task 1.

---

### Task 1: `usage-cache.py` helper with fixtures and tests

**Files:**
- Create: `skills/check-usage/scripts/usage-cache.py`
- Create: `tests/fixtures/cache-max5x.json`
- Create: `tests/fixtures/cache-credits-on.json`
- Create: `tests/fixtures/cache-other-account.json`
- Create: `tests/fixtures/cache-malformed.json`
- Create: `tests/fixtures/cache-partial.json`
- Modify: `tests/test-check-usage.sh` (add a section above `# --- summary`)

**Interfaces:**
- Produces: `python3 usage-cache.py <config.json>` prints 0–4 lines, each starting with one of `Plan: `, `Binding limit: `, `Usage credits: `, or a credit label ending in `: $<rem> of $<lim> left`. Env: `CHECK_USAGE_NOW_MS` (epoch ms, tests), `CHECK_USAGE_CACHE_MAX_AGE` (seconds, default 180). The exact `Usage credits:` prefixes `Usage credits: ON ·`, `Usage credits: ON but out of credits`, `Usage credits: OFF` are consumed by Task 2.
- Test globals produced for later tasks: `NOW_MS=1791094954300`, `CACHE_PY="$(dirname "$SCRIPT")/usage-cache.py"`.

- [ ] **Step 1: Create fixtures**

`tests/fixtures/cache-max5x.json`:
```json
{
  "oauthAccount": {
    "accountUuid": "00000000-0000-0000-0000-000000000001",
    "organizationRateLimitTier": "default_claude_max_5x",
    "organizationType": "claude_max",
    "emailAddress": "someone@example.com"
  },
  "cachedUsageUtilization": {
    "fetchedAtMs": 1791094924300,
    "accountUuid": "00000000-0000-0000-0000-000000000001",
    "utilization": {
      "five_hour": {"utilization": 84, "resets_at": "2026-10-04T09:00:00+00:00", "limit_dollars": null, "used_dollars": null, "remaining_dollars": null},
      "seven_day": {"utilization": 11, "resets_at": "2026-10-11T04:00:00+00:00", "limit_dollars": null, "used_dollars": null, "remaining_dollars": null},
      "iguana_necktie": {"utilization": 58.749594, "resets_at": "2026-11-05T07:59:00+00:00", "limit_dollars": 250, "used_dollars": 146.873985, "remaining_dollars": 103.126015, "locked_reason": null},
      "extra_usage": {"is_enabled": false, "monthly_limit": null, "used_credits": 0, "currency": "GBP", "decimal_places": 2, "disabled_reason": "out_of_credits", "user_disabled": false},
      "spend": {"balance": null, "enabled": false, "disabled_reason": "out_of_credits"},
      "limits": [
        {"kind": "session", "group": "session", "percent": 84, "severity": "warning", "scope": null, "is_active": true},
        {"kind": "weekly_all", "group": "weekly", "percent": 11, "severity": "normal", "scope": null, "is_active": false},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 3, "severity": "normal", "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}
      ]
    }
  }
}
```

`tests/fixtures/cache-credits-on.json`:
```json
{
  "oauthAccount": {"accountUuid": "00000000-0000-0000-0000-000000000002", "organizationRateLimitTier": "default_claude_pro"},
  "cachedUsageUtilization": {
    "fetchedAtMs": 1791094924300,
    "accountUuid": "00000000-0000-0000-0000-000000000002",
    "utilization": {
      "extra_usage": {"is_enabled": true, "monthly_limit": 2500, "used_credits": 1260, "currency": "GBP", "decimal_places": 2, "disabled_reason": null, "user_disabled": false},
      "limits": [
        {"kind": "session", "percent": 40, "is_active": false},
        {"kind": "weekly_all", "percent": 100, "is_active": true}
      ]
    }
  }
}
```

`tests/fixtures/cache-other-account.json`: copy of `cache-max5x.json` with `oauthAccount.accountUuid` changed to `00000000-0000-0000-0000-000000000009` (cache `accountUuid` stays `…0001`).

`tests/fixtures/cache-malformed.json`:
```
{not json
```

`tests/fixtures/cache-partial.json`:
```json
{"oauthAccount": {}, "cachedUsageUtilization": {"fetchedAtMs": 1791094924300, "utilization": {"limits": "not-a-list", "extra_usage": "nope"}}}
```

- [ ] **Step 2: Append failing tests**

Insert above `# --- summary` in `tests/test-check-usage.sh`:
```bash
# --- Enrichment helper (usage-cache.py) -------------------------------------

NOW_MS=1791094954300   # 30 s after the fixtures' fetchedAtMs
CACHE_PY="$(dirname "$SCRIPT")/usage-cache.py"

if command -v python3 >/dev/null 2>&1; then
  run_cache_py() { # CACHE_FILE [NOW_MS] -> sets out, rc
    out="$(CHECK_USAGE_NOW_MS="${2:-$NOW_MS}" python3 "$CACHE_PY" "$1" 2>&1)"
    rc=$?
  }

  run_cache_py "$FIX/cache-max5x.json"
  assert_eq       "cache max5x: exit 0" 0 "$rc"
  assert_contains "cache max5x: plan" "$out" "Plan: Max 5x"
  assert_contains "cache max5x: binding limit" "$out" "Binding limit: session 84%"
  assert_contains "cache max5x: out of credits" "$out" "Usage credits: ON but out of credits (balance £0.00), so work stops when a plan limit is hit"
  assert_contains "cache max5x: cloud credit" "$out" "Cloud session credit (cloud sessions only): \$103.13 of \$250.00 left · expires Nov 5"
  assert_not_contains "cache max5x: no obfuscated key" "$out" "iguana"
  assert_not_contains "cache max5x: no email" "$out" "example.com"
  assert_not_contains "cache max5x: no uuid" "$out" "00000000-"

  run_cache_py "$FIX/cache-credits-on.json"
  assert_contains "cache credits on: pro plan note" "$out" "Plan: Pro (Fable models are not included; they always use usage credits)"
  assert_contains "cache credits on: weekly binding" "$out" "Binding limit: weekly (all models) 100%"
  assert_contains "cache credits on: billed" "$out" "Usage credits: ON · £12.60 used of £25.00 monthly limit (work past a plan limit is billed at API rates)"

  run_cache_py "$FIX/cache-max5x.json" 1791095524300   # 600 s later
  assert_eq "cache stale: exit 0" 0 "$rc"
  assert_eq "cache stale: no output" "" "$out"

  run_cache_py "$FIX/cache-max5x.json" 1791094000000   # cache 15 min in the future
  assert_eq "cache future: no output" "" "$out"

  run_cache_py "$FIX/cache-other-account.json"
  assert_eq "cache other account: no output" "" "$out"

  run_cache_py "$FIX/cache-malformed.json"
  assert_eq "cache malformed: exit 0" 0 "$rc"
  assert_eq "cache malformed: no output" "" "$out"

  run_cache_py "$FIX/cache-partial.json"
  assert_eq "cache partial: exit 0" 0 "$rc"
  assert_not_contains "cache partial: no traceback" "$out" "Traceback"

  run_cache_py "$TMP/does-not-exist.json"
  assert_eq "cache missing: exit 0" 0 "$rc"
  assert_eq "cache missing: no output" "" "$out"
else
  echo "SKIP: python3 not found; enrichment helper tests skipped"
fi
```

- [ ] **Step 3: Run tests, verify the new ones fail**

Run: `bash tests/test-check-usage.sh`
Expected: existing 47 pass; new assertions fail (helper file does not exist). Exit 1.

- [ ] **Step 4: Write the helper**

`skills/check-usage/scripts/usage-cache.py`:
```python
#!/usr/bin/env python3
"""Best-effort enrichment for check-usage from Claude Code's local usage cache.

Usage: usage-cache.py <path to Claude Code config JSON, e.g. ~/.claude.json>

Prints zero or more report lines. Prints nothing and exits 0 on any problem:
missing file, bad JSON, stale or mismatched cache, unknown shape. The cache is
undocumented, so this must never fail loudly.

Environment:
  CHECK_USAGE_NOW_MS         current time in epoch milliseconds (tests); default: now
  CHECK_USAGE_CACHE_MAX_AGE  maximum cache age in seconds; default 180
"""
import json
import os
import sys
import time
from datetime import datetime

TIERS = {
    "default_claude_pro": "Pro",
    "default_claude_max_5x": "Max 5x",
    "default_claude_max_20x": "Max 20x",
}
CURRENCY_SYMBOLS = {"GBP": "£", "USD": "$", "EUR": "€"}
# Dollar-denominated credit buckets. Keys are server-side codenames; never print them.
CREDIT_LABELS = {
    "iguana_necktie": "Cloud session credit (cloud sessions only)",
    "cinder_cove": "Claude Code and Cowork credit",
}
NOT_CREDIT_BUCKETS = {"five_hour", "seven_day"}
FUTURE_TOLERANCE_MS = 60_000


def money(minor, currency, places):
    symbol = CURRENCY_SYMBOLS.get(currency or "", (currency + " ") if currency else "")
    return f"{symbol}{minor / (10 ** places):.{places}f}"


def limit_label(entry):
    kind = entry.get("kind")
    if kind == "session":
        return "session"
    if kind == "weekly_all":
        return "weekly (all models)"
    if kind == "weekly_scoped":
        scope = entry.get("scope") or {}
        model = scope.get("model") or {} if isinstance(scope, dict) else {}
        return f"weekly ({model.get('display_name') or 'scoped'})"
    return str(kind or "unknown")


def short_date(iso):
    try:
        d = datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
        return f"{d.strftime('%b')} {d.day}"
    except (TypeError, ValueError):
        return None


def plan_line(account):
    tier = account.get("organizationRateLimitTier") or account.get("userRateLimitTier")
    if not tier:
        return None
    name = TIERS.get(tier, tier)
    if tier == "default_claude_pro":
        name += " (Fable models are not included; they always use usage credits)"
    return f"Plan: {name}"


def binding_line(util):
    limits = util.get("limits")
    if not isinstance(limits, list):
        return None
    for entry in limits:
        if isinstance(entry, dict) and entry.get("is_active"):
            pct = entry.get("percent")
            suffix = f" {pct:g}%" if isinstance(pct, (int, float)) else ""
            return f"Binding limit: {limit_label(entry)}{suffix}"
    return None


def credits_line(util):
    extra = util.get("extra_usage")
    if not isinstance(extra, dict):
        return None
    currency = extra.get("currency")
    places = extra.get("decimal_places")
    places = places if isinstance(places, int) else 2
    if extra.get("is_enabled"):
        line = "Usage credits: ON"
        used = extra.get("used_credits")
        if isinstance(used, (int, float)):
            line += f" · {money(used, currency, places)} used"
            limit = extra.get("monthly_limit")
            if isinstance(limit, (int, float)):
                line += f" of {money(limit, currency, places)} monthly limit"
        return line + " (work past a plan limit is billed at API rates)"
    reason = extra.get("disabled_reason")
    if reason == "out_of_credits":
        return (f"Usage credits: ON but out of credits (balance {money(0, currency, places)}), "
                "so work stops when a plan limit is hit")
    detail = f" ({reason})" if reason and not extra.get("user_disabled") else ""
    return f"Usage credits: OFF{detail}, so work stops when a plan limit is hit"


def credit_bucket_lines(util):
    lines = []
    for key, bucket in util.items():
        if key in NOT_CREDIT_BUCKETS or not isinstance(bucket, dict):
            continue
        limit = bucket.get("limit_dollars")
        if not isinstance(limit, (int, float)):
            continue
        remaining = bucket.get("remaining_dollars")
        if not isinstance(remaining, (int, float)):
            used = bucket.get("used_dollars")
            remaining = limit - used if isinstance(used, (int, float)) else None
        if remaining is None:
            continue
        label = CREDIT_LABELS.get(key, "Included credit")
        line = f"{label}: ${remaining:.2f} of ${limit:.2f} left"
        expires = short_date(bucket.get("resets_at"))
        if expires:
            line += f" · expires {expires}"
        lines.append(line)
    return lines


def report(cfg, now_ms, max_age_s):
    if not isinstance(cfg, dict):
        return []
    cache = cfg.get("cachedUsageUtilization")
    account = cfg.get("oauthAccount")
    account = account if isinstance(account, dict) else {}
    if not isinstance(cache, dict) or not isinstance(cache.get("utilization"), dict):
        return []
    fetched = cache.get("fetchedAtMs")
    if not isinstance(fetched, (int, float)):
        return []
    if now_ms - fetched > max_age_s * 1000 or fetched - now_ms > FUTURE_TOLERANCE_MS:
        return []
    cache_account, profile_account = cache.get("accountUuid"), account.get("accountUuid")
    if cache_account and profile_account and cache_account != profile_account:
        return []
    util = cache["utilization"]
    lines = [plan_line(account), binding_line(util), credits_line(util)]
    lines += credit_bucket_lines(util)
    return [line for line in lines if line]


def main():
    if len(sys.argv) < 2:
        return
    try:
        with open(sys.argv[1], encoding="utf-8") as f:
            cfg = json.load(f)
        now_ms = int(os.environ.get("CHECK_USAGE_NOW_MS") or time.time() * 1000)
        max_age_s = int(os.environ.get("CHECK_USAGE_CACHE_MAX_AGE") or 180)
        for line in report(cfg, now_ms, max_age_s):
            print(line)
    except Exception:  # undocumented input: stay silent rather than break the report
        return


if __name__ == "__main__":
    main()
```

Note: `monthly_limit` and `used_credits` are treated as minor units (consistent with `decimal_places`). The live account has never had a funded balance, so this is unverified; the fixture pins the assumption.

- [ ] **Step 5: Run tests, verify pass**

Run: `bash tests/test-check-usage.sh` — expect `… 0 failed`.
Also run the helper once against the real cache to confirm it reads live data without error (output goes only to your report; do not paste personal fields):
`claude -p "/usage" >/dev/null 2>&1; python3 skills/check-usage/scripts/usage-cache.py ~/.claude.json`
Expected: 3–4 lines starting `Plan: Max 5x`, `Binding limit:`, `Usage credits:`, and a cloud credit line.

- [ ] **Step 6: Commit**

```bash
git add skills/check-usage/scripts/usage-cache.py tests/
git commit -m "Add best-effort usage-cache helper for plan, binding limit and credits

Reads Claude Code's local usage cache (fresh, same account only) and
prints plan tier, the binding limit, usage-credits state and included
credit buckets. Silent on any problem; never prints personal fields or
server codenames.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ub6MrWMjj4X3nxSh8jzwKV"
```

---

### Task 2: Wire enrichment into `check-usage.sh`, definitive WARNING, plan-shape fixtures

**Files:**
- Modify: `skills/check-usage/scripts/check-usage.sh`
- Modify: `tests/test-check-usage.sh` (append above `# --- summary`)
- Create: `tests/fixtures/pro-two-line.txt`
- Create: `tests/fixtures/max-sonnet-only.txt`

**Interfaces:**
- Consumes: `usage-cache.py` and its `Usage credits:` prefixes; test globals `NOW_MS`, `$TMP`, `$TMP/sentinel`.
- Produces env knobs: `CHECK_USAGE_CACHE_FILE` (config JSON path), `CHECK_USAGE_NO_CACHE` (non-empty disables), `CHECK_USAGE_PYTHON` (interpreter, default `python3`). New output: a blank line then the helper's lines; under WARNING, one `Credits check:` line when credits state is known.

- [ ] **Step 1: Create fixtures**

`tests/fixtures/pro-two-line.txt`:
```
Current session: 40% used · resets Oct 4 at 1pm (Europe/London)
Current week (all models): 62% used · resets Oct 9 at 5am (Europe/London)
```

`tests/fixtures/max-sonnet-only.txt`:
```
Current session: 15% used · resets Oct 4 at 1pm (Europe/London)
Current week (all models): 70% used · resets Oct 9 at 5am (Europe/London)
Current week (Sonnet only): 100% used · resets Oct 9 at 5am (Europe/London)
```

- [ ] **Step 2: Append failing tests**

```bash
# --- Enrichment wiring --------------------------------------------------------

run_with_cache() { # FIXTURE CACHE_FILE [VAR=value ...] -> sets out, rc
  local fx="$1" cf="$2"
  shift 2
  out="$(env CHECK_USAGE_INPUT_FILE="$fx" CHECK_USAGE_CLAUDE_BIN="$TMP/sentinel" \
    CHECK_USAGE_CACHE_FILE="$cf" CHECK_USAGE_NOW_MS="$NOW_MS" "$@" bash "$SCRIPT" 2>&1)"
  rc=$?
}

if command -v python3 >/dev/null 2>&1; then
  run_with_cache "$FIX/weekly-exhausted.txt" "$FIX/cache-max5x.json"
  assert_eq       "wired out-of-credits: exit 0" 0 "$rc"
  assert_contains "wired out-of-credits: WARNING kept" "$out" "WARNING: weekly quota is exhausted (100%)"
  assert_contains "wired out-of-credits: plan line" "$out" "Plan: Max 5x"
  assert_contains "wired out-of-credits: credits check stop" "$out" "Credits check: usage credits are unavailable (see the Usage credits line), so this is a hard stop, not a bill."

  run_with_cache "$FIX/weekly-exhausted.txt" "$FIX/cache-credits-on.json"
  assert_contains "wired credits on: credits check billed" "$out" "Credits check: usage credits are enabled, so work past 100% is being billed at API rates."

  run_with_cache "$FIX/weekly-exhausted.txt" "$FIX/cache-max5x.json" CHECK_USAGE_NOW_MS=1791095524300
  assert_contains     "wired stale: WARNING kept" "$out" "WARNING: weekly quota is exhausted"
  assert_not_contains "wired stale: no plan line" "$out" "Plan:"
  assert_not_contains "wired stale: no credits check" "$out" "Credits check:"

  run_with_cache "$FIX/normal.txt" "$FIX/cache-max5x.json" CHECK_USAGE_NO_CACHE=1
  assert_not_contains "wired no-cache flag: no plan line" "$out" "Plan:"

  run_with_cache "$FIX/normal.txt" "$FIX/cache-max5x.json" CHECK_USAGE_PYTHON="$TMP/no-such-python"
  assert_eq           "wired python missing: exit 0" 0 "$rc"
  assert_not_contains "wired python missing: no plan line" "$out" "Plan:"
  assert_contains     "wired python missing: figures still printed" "$out" "Current session: 23% used"

  run_with_cache "$FIX/normal.txt" "$FIX/cache-max5x.json"
  assert_not_contains "wired normal: no credits check without WARNING" "$out" "Credits check:"
  assert_contains     "wired normal: binding limit line" "$out" "Binding limit: session 84%"

  # Canned mode must not read the real config even when HOME holds a valid cache.
  mkdir -p "$TMP/home"
  cp "$FIX/cache-max5x.json" "$TMP/home/.claude.json"
  out="$(env -u CLAUDE_CONFIG_DIR HOME="$TMP/home" CHECK_USAGE_INPUT_FILE="$FIX/normal.txt" \
    CHECK_USAGE_CLAUDE_BIN="$TMP/sentinel" CHECK_USAGE_NOW_MS="$NOW_MS" bash "$SCRIPT" 2>&1)"
  assert_not_contains "canned mode ignores HOME cache" "$out" "Plan:"
fi

# --- Plan shapes --------------------------------------------------------------

run_with_file "$FIX/pro-two-line.txt"
assert_eq           "pro two-line: exit 0" 0 "$rc"
assert_contains     "pro two-line: week relayed" "$out" "Current week (all models): 62% used"
assert_not_contains "pro two-line: no WARNING" "$out" "WARNING"

run_with_file "$FIX/max-sonnet-only.txt"
assert_contains     "sonnet-only: per-model line relayed" "$out" "Current week (Sonnet only): 100% used"
assert_not_contains "sonnet-only: per-model 100% is not a WARNING" "$out" "WARNING"
assert_not_contains "sonnet-only: per-model 100% is not a NOTICE" "$out" "NOTICE"
```

Note on `env -u`: macOS `/usr/bin/env` supports `-u`. If the implementer finds it does not, use `(unset CLAUDE_CONFIG_DIR; HOME=… … bash "$SCRIPT")` instead.

- [ ] **Step 3: Run tests, verify the new wiring tests fail** (plan-shape tests may already pass; that is fine, they pin current behaviour).

- [ ] **Step 4: Implement**

In `check-usage.sh`, extend the header comment's Environment list:
```bash
#   CHECK_USAGE_CACHE_FILE  Claude Code config JSON to read plan/credits from (default in live mode:
#                           ${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json; canned mode reads none unless set)
#   CHECK_USAGE_NO_CACHE    set to anything non-empty to skip the plan/credits lines
#   CHECK_USAGE_PYTHON      python interpreter for the plan/credits lines (default: python3; optional)
```

After `claude_bin=…` add:
```bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python_bin="${CHECK_USAGE_PYTHON:-python3}"
```

Replace the single line `echo "$matched"` with:
```bash
echo "$matched"

# Best-effort plan/credits lines from Claude Code's local usage cache (refreshed by the
# /usage call above). Silent when python3, the cache, or a fresh same-account entry is missing.
enrich=""
if [ -z "${CHECK_USAGE_NO_CACHE:-}" ] && command -v "$python_bin" >/dev/null 2>&1; then
  if [ -n "${CHECK_USAGE_CACHE_FILE:-}" ]; then
    cache_file="$CHECK_USAGE_CACHE_FILE"
  elif [ -z "${CHECK_USAGE_INPUT_FILE:-}" ]; then
    cache_file="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
  else
    cache_file=""
  fi
  if [ -n "$cache_file" ] && [ -f "$cache_file" ]; then
    enrich="$("$python_bin" "$script_dir/usage-cache.py" "$cache_file" 2>/dev/null || true)"
  fi
fi
if [ -n "$enrich" ]; then
  echo
  echo "$enrich"
fi
```

Inside the WARNING branch, after its fourth `echo`, add:
```bash
  if echo "$enrich" | grep -q '^Usage credits: ON ·'; then
    echo "Credits check: usage credits are enabled, so work past 100% is being billed at API rates."
  elif echo "$enrich" | grep -q '^Usage credits:'; then
    echo "Credits check: usage credits are unavailable (see the Usage credits line), so this is a hard stop, not a bill."
  fi
```

- [ ] **Step 5: Run tests (expect 0 failed), then run the live script once:** `bash skills/check-usage/scripts/check-usage.sh` — expect the `Current …` lines, a blank line, then `Plan: Max 5x`, `Binding limit: …`, `Usage credits: …` and a credit line. Exit 0.

- [ ] **Step 6: Commit**

```bash
git add skills/check-usage/scripts/check-usage.sh tests/
git commit -m "Print plan and credits lines; make weekly WARNING say bill or stop

check-usage.sh appends the usage-cache helper's lines after the figures
(live mode reads the real config; canned mode only an explicit file) and
adds a Credits check line under the WARNING when credits state is known.
Adds Pro two-line and Sonnet-only fixtures.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ub6MrWMjj4X3nxSh8jzwKV"
```

---

### Task 3: SKILL.md and README

**Files:**
- Modify: `skills/check-usage/SKILL.md`
- Modify: `README.md`

**Interfaces:** consumes the output lines from Tasks 1–2. Documentation only.

- [ ] **Step 1: SKILL.md — replace the per-model paragraph** in "What the script prints" (the sentence beginning "A per-model week line (e.g. `(Fable)`) may also appear") with:
```markdown
A per-model week line (e.g. `(Fable)` or `(Sonnet only)`) is a sub-cap inside the weekly pool, not
extra capacity. The session and weekly (all models) limits apply to every model, so per-model room
never helps when either of those is exhausted. Mention the per-model line briefly, or lead with it
when the `Binding limit:` line names it or it is at 90% or more. Once a per-model cap is hit, that
model needs usage credits while other models keep working.
```

- [ ] **Step 2: SKILL.md — insert a new section** after "What the script prints" and before "When the script cannot get numbers":
```markdown
## Plan and credits lines (best effort)

After the figures the script may print lines read from Claude Code's local usage cache. They are
best effort (undocumented, shown only when the cache is fresh) and may be absent:

- `Plan: …` is the subscription tier. On Pro, and on Team or Enterprise standard seats, Fable models
  are not included and always run on usage credits.
- `Binding limit: …` is the limit currently constraining the account. Use it as the headline.
- `Usage credits: …` says whether work past a plan limit is billed or stops. `ON · … used` means it
  is billed at API rates. `ON but out of credits` or `OFF` means a hard stop at 100%, whatever the
  toggle in settings shows.
- `Cloud session credit: …` or another `… credit: $X of $Y left` line is a separate included credit
  with its own expiry. It covers only what its label says (for example cloud sessions), not local
  Claude Code work.
- `Credits check: …` under a WARNING settles whether the WARNING means a bill or a stop. Relay it.

When these lines are absent, fall back to the WARNING's either/or wording.
```

- [ ] **Step 3: SKILL.md — "Interpreting numbers the user already has"**: append this paragraph to the end of that section:
```markdown
If the user says usage credits are switched on but the balance is zero and auto-reload is off, treat
credits as unavailable: weekly at 100% is then a hard stop at the next request, not a bill. Say so
plainly, and point to `/usage-credits` to add credits or turn on auto-reload. Promotional credits, if
the account has any, are spent before purchased credits.
```

- [ ] **Step 4: SKILL.md — decision rule**: change the bullet `**Weekly ≥ 100% (WARNING):** flag it first, as above. Continuing is the user's call, never silent.` to:
```markdown
- **Weekly ≥ 100% (WARNING):** flag it first, as above. If credits are unavailable (a `Credits
  check:` stop line, or the user says the balance is zero), say work will stop at the next request.
  Continuing on credits is the user's call, never silent.
```

- [ ] **Step 5: README** — after the "Two situations get an extra block…" bullets in "What it reports", add:
```markdown
After the figures, the script adds best-effort lines from Claude Code's local usage cache when
`python3` is available and the cache is fresh (it is refreshed by the same `/usage` call):

```
Plan: Max 5x
Binding limit: weekly (all models) 89%
Usage credits: ON but out of credits (balance £0.00), so work stops when a plan limit is hit
Cloud session credit (cloud sessions only): $103.13 of $250.00 left · expires Nov 5
```

Under a WARNING it also adds a `Credits check:` line saying whether work past 100% is being billed
or will stop. The cache is undocumented, so these lines may disappear after a Claude Code update;
the figures above them never depend on it. See `docs/research/2026-10-03-plan-limits-and-credits.md`
for how session, weekly, per-model limits and the different credits interact.
```
In the Testing section's env-var bullets, add:
```markdown
- `CHECK_USAGE_CACHE_FILE=<path>` reads plan/credits from this config JSON (canned mode reads none
  unless this is set). `CHECK_USAGE_NO_CACHE=1` turns the lines off. `CHECK_USAGE_PYTHON` picks the
  interpreter.
```
In Requirements add: `- python3 (optional) for the plan and credits lines.`

- [ ] **Step 6: Check** `head -4 skills/check-usage/SKILL.md` frontmatter unchanged; `bash tests/test-check-usage.sh` → 0 failed.

- [ ] **Step 7: Commit** with message `Document plan and credits lines; per-model limits are sub-caps` and the trailer lines.

---

### Task 4: Eval case, FINDINGS status, pilot

**Files:**
- Create: `evals/07-pasted-out-of-credits/prompt.md`
- Create: `evals/07-pasted-out-of-credits/graders/says-work-stops.md`
- Create: `evals/07-pasted-out-of-credits/graders/stop-not-bill.md`
- Create: `evals/07-pasted-out-of-credits/graders/skill-fired.md`
- Modify: `evals/FINDINGS.md` (E1 status line)

- [ ] **Step 1: Create the case**

`prompt.md`:
```markdown
---
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, "Bash(bash:*)"]
runs: 3
---
I ran /usage and got:

Current session: 22% used · resets Oct 9 at 3pm (Europe/London)
Current week (all models): 100% used · resets Oct 11 at 5am (Europe/London)
Current week (Fable): 41% used · resets Oct 11 at 5am (Europe/London)

Usage credits are switched on in my settings, but the balance is £0 and auto-reload is off. I'm on step 2 of 6 of a refactor. Can I keep going?
```

`graders/says-work-stops.md`:
```markdown
---
type: regex
target: last_message
match: contains
flags: i
---
(hard stop|will stop|stop at the next|be blocked|blocked until|cut off|can't continue|cannot continue|won't be able to continue|not be able to continue)
```

`graders/stop-not-bill.md`:
```markdown
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
```

`graders/skill-fired.md`:
```markdown
---
type: tool_used
tool: Skill
input_match: check-usage
min: 1
---
```

- [ ] **Step 2: FINDINGS** — under E1's existing Status line, append on a new paragraph:
`**Status (2026-10-04):** implemented in <hash Task 1>..<hash Task 3> — plan, binding-limit, usage-credits and included-credit lines from the local cache; definitive Credits check under the WARNING; per-model sub-cap rule in SKILL.md; eval case 07. Team/Enterprise /usage shapes remain unobserved.`
Fill in the real hashes from `git log --oneline -4`.

- [ ] **Step 3: Pilot** (≈ $4, 6–8 minutes; run once):
```bash
claude plugin eval . --runs 1 --ablation with-without --no-scaffold --no-publish --judge-model sonnet --allow-tools "Bash(bash:*)" 2>&1 | tail -16
```
Record in the report: the full summary table; for case 07 whether the skill fired and the Δ; that 05/06 negatives still show `skill-not-fired` 0x in both arms; no `⚠ case … cannot pass` notices. Do not edit any skill file based on the result; report it.

- [ ] **Step 4: Commit** `evals/07-pasted-out-of-credits evals/FINDINGS.md` with message `Add out-of-credits eval case; record E1 implementation status` and the trailer lines. Do not push.
