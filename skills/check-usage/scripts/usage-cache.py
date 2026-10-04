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
