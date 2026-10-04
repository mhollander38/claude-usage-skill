#!/usr/bin/env python3
"""Best-effort enrichment for check-usage from Claude Code's local usage cache.

Usage: usage-cache.py <path to Claude Code config JSON, e.g. ~/.claude.json>

Prints zero or more report lines. Prints nothing and exits 0 on any problem:
missing file, bad JSON, stale or mismatched cache, unknown shape. The cache is
undocumented, so this must never fail loudly.

Environment:
  CHECK_USAGE_NOW_MS         current time in epoch milliseconds (tests); default: now
  CHECK_USAGE_CACHE_MAX_AGE  maximum cache age in seconds; default 180
  CHECK_USAGE_CLI_VERSION    Claude Code version, e.g. 2.1.289; gates the wrap-up allowance line
  CHECK_USAGE_DEBUG          non-empty: let errors propagate instead of staying silent (tests)

The last line printed (when a credits line exists) is "Credits state: billed|stop|local",
an internal marker for check-usage.sh that is never shown to the user.
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
    "claude_team": "Team",
    "claude_enterprise": "Enterprise",
}
KNOWN_OFF_REASONS = {
    "org_level_disabled",
    "org_level_disabled_until",
    "member_level_disabled",
    "seat_tier_level_disabled",
    "overage_not_provisioned",
}
LOCAL_CREDIT_NOTE = (
    "Local included credit available: work past a plan limit may draw on it before stopping."
)
CURRENCY_SYMBOLS = {"GBP": "£", "USD": "$", "EUR": "€"}
# Dollar-denominated credit buckets. Keys are server-side codenames; never print them.
CREDIT_LABELS = {
    "iguana_necktie": "Cloud session credit (cloud sessions only)",
    "cinder_cove": "Claude Code and Cowork credit",
}
# Buckets known to cover Claude Code work locally. Unknown buckets are listed but never
# change the credits state.
LOCAL_CREDIT_KEYS = {"cinder_cove"}
NOT_CREDIT_BUCKETS = {"five_hour", "seven_day"}
FUTURE_TOLERANCE_MS = 60_000
WRAP_UP_MIN_VERSION = (2, 1, 277)
WRAP_UP_TIERS = {"default_claude_pro", "default_claude_max_5x", "default_claude_max_20x"}
WRAP_UP_SESSION_PERCENT = 80
WEEKLY_EXHAUSTED_PERCENT = 100
WRAP_UP_BASE = (
    "Wrap-up allowance: if the 5-hour limit is reached mid-response, Claude Code may "
    'keep working briefly to a stopping point ("Usage limit reached · wrapping up"). '
    "It counts toward the weekly limit and never covers starting new work."
)


def money(minor, currency, places):
    currency = currency if isinstance(currency, str) else None
    symbol = CURRENCY_SYMBOLS.get(currency or "", (currency + " ") if currency else "")
    return f"{symbol}{minor / (10**places):.{places}f}"


def limit_label(entry):
    kind = entry.get("kind")
    if kind == "session":
        return "session"
    if kind == "weekly_all":
        return "weekly (all models)"
    if kind == "weekly_scoped":
        scope = entry.get("scope")
        model = scope.get("model") if isinstance(scope, dict) else None
        name = model.get("display_name") if isinstance(model, dict) else None
        return f"weekly ({name or 'scoped'})"
    return "another limit"


def short_date(iso):
    try:
        d = datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
        return f"{d.strftime('%b')} {d.day}"
    except (TypeError, ValueError, AttributeError):
        return None


def account_tier(account):
    return account.get("organizationRateLimitTier") or account.get("userRateLimitTier")


def plan_line(account):
    tier = account_tier(account)
    if not tier:
        return None
    name = TIERS.get(tier, "unrecognised tier") if isinstance(tier, str) else "unrecognised tier"
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
    """Return (line, state) with state "billed" or "stop", or None without extra_usage."""
    extra = util.get("extra_usage")
    if not isinstance(extra, dict):
        return None
    currency = extra.get("currency")
    places = extra.get("decimal_places")
    places = places if isinstance(places, int) else 2
    if extra.get("is_enabled"):
        line = "Usage credits: ON"
        used = extra.get("used_credits")
        limit = extra.get("monthly_limit")
        numeric = (int, float)
        if isinstance(used, numeric) and isinstance(limit, numeric) and used >= limit:
            return (
                f"Usage credits: ON but monthly spend limit reached "
                f"({money(used, currency, places)} of {money(limit, currency, places)}), "
                "so work stops when a plan limit is hit",
                "stop",
            )
        if isinstance(used, numeric):
            line += f" · {money(used, currency, places)} used"
            if isinstance(limit, numeric):
                line += f" of {money(limit, currency, places)} monthly limit"
        return line + " (work past a plan limit is billed at API rates)", "billed"
    stop = ", so work stops when a plan limit is hit"
    if extra.get("user_disabled"):
        return "Usage credits: OFF (turned off in settings)" + stop, "stop"
    reason = extra.get("disabled_reason")
    if reason == "out_of_credits":
        balance = f" (balance {money(0, currency, places)})" if isinstance(currency, str) else ""
        return f"Usage credits: ON but out of credits{balance}" + stop, "stop"
    detail = f" ({reason})" if reason in KNOWN_OFF_REASONS else ""
    return f"Usage credits: OFF{detail}" + stop, "stop"


def credit_buckets(util):
    """Return a list of (key, remaining, line) for each dollar credit bucket."""
    found = []
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
        found.append((key, remaining, line))
    return found


def credit_bucket_lines(util):
    return [line for _, _, line in credit_buckets(util)]


def local_credit_available(util):
    return any(
        remaining > 0 for key, remaining, _ in credit_buckets(util) if key in LOCAL_CREDIT_KEYS
    )


def parse_version(text):
    parts = str(text or "").strip().split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        return None
    return tuple(int(p) for p in parts)


def wrap_up_line(account, util, credits_state):
    version = parse_version(os.environ.get("CHECK_USAGE_CLI_VERSION"))
    if version is None or version < WRAP_UP_MIN_VERSION:
        return None
    tier = account_tier(account)
    if tier not in WRAP_UP_TIERS:
        return None
    limits = util.get("limits")
    if not isinstance(limits, list):
        return None
    session = next((e for e in limits if isinstance(e, dict) and e.get("kind") == "session"), None)
    pct = session.get("percent") if session else None
    if not isinstance(pct, (int, float)) or pct < WRAP_UP_SESSION_PERCENT:
        return None
    weekly = next(
        (e for e in limits if isinstance(e, dict) and e.get("kind") == "weekly_all"), None
    )
    week_pct = weekly.get("percent") if weekly else None
    if isinstance(week_pct, (int, float)) and week_pct >= WEEKLY_EXHAUSTED_PERCENT:
        return None
    line = WRAP_UP_BASE
    if tier == "default_claude_pro":
        line += " On Pro it is available up to once per weekly period."
    if credits_state == "billed":
        line += " With usage credits on, the wrap-up is used first, then credits."
    return line


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
    if profile_account and cache_account != profile_account:
        return []
    util = cache["utilization"]
    lines = []

    def section(fn, *args):
        try:
            return fn(*args)
        except Exception:  # undocumented input: one bad section must not break the rest
            if os.environ.get("CHECK_USAGE_DEBUG"):
                raise
            return None

    plan = section(plan_line, account)
    binding = section(binding_line, util)
    credits = section(credits_line, util)
    credits_text, state = credits if credits else (None, None)
    buckets = section(credit_bucket_lines, util) or []
    for line in (plan, binding, credits_text):
        if line:
            lines.append(line)
    lines += buckets
    if state == "stop" and section(local_credit_available, util):
        state = "local"
        lines.append(LOCAL_CREDIT_NOTE)
    wrap_up = section(wrap_up_line, account, util, state)
    if wrap_up:
        lines.append(wrap_up)
    if state:
        lines.append(f"Credits state: {state}")
    return lines


def main():
    if len(sys.argv) < 2:
        return
    try:
        with open(sys.argv[1], encoding="utf-8") as f:
            cfg = json.load(f)
        now_ms = int(os.environ.get("CHECK_USAGE_NOW_MS") or time.time() * 1000)
        max_age_s = int(os.environ.get("CHECK_USAGE_CACHE_MAX_AGE") or 180)
        lines = report(cfg, now_ms, max_age_s)
        if lines:
            print("\n".join(lines))
    except Exception:  # undocumented input: stay silent, never break the report
        if os.environ.get("CHECK_USAGE_DEBUG"):
            raise


if __name__ == "__main__":
    main()
