# How Claude plan limits, per-model allowances and credits actually work (2026-10-03)

Research for `evals/FINDINGS.md` section E1. Sources: Anthropic support articles and Claude Code docs
(linked at the end), the Claude Code 2.1.288 binary, this account's local config and cached usage
response, and the claude.ai Settings > Usage page. Account under test: Max 5x, GBP billing.

## 1. The limits, and why the session limit binds while "Fable only" shows room

There are three kinds of limit on a Max plan. They are nested, not additive.

| limit | window | applies to | source of truth |
|---|---|---|---|
| Session | rolling 5 hours | **every model** | `five_hour` |
| Weekly (all models) | 7 days, fixed reset time assigned per account | **every model** | `seven_day` |
| Per-model weekly (e.g. "Fable this week") | same 7-day window | that model family only | `limits[]` entry with `kind: weekly_scoped`, `scope.model.display_name: "Fable"` |

- Claude Code docs: "The session and weekly limits are shared across all models, so switching models
  doesn't restore access. The Opus and Sonnet limits each apply only to requests to that model
  family". Fable follows the same model-scoped pattern (the server labels the bucket; the client
  renders `Current week (<display_name>)`).
- Anthropic on Fable: "You can use up to 50% of your weekly usage limits on Fable models at no extra
  cost. They draw from your plan's regular weekly usage limits." The claude.ai usage page labels the
  bar "Separate weekly limit for Fable".

So the "Fable only" bar is a **sub-cap of the weekly pool**, not extra capacity. Fable requests burn
the session window and the all-models weekly window exactly like any other model, and additionally
count against the Fable sub-cap. When the 5-hour session window is exhausted, Fable stops too,
however much Fable weekly room remains. Conversely, once the Fable sub-cap is hit, Fable needs
usage credits while other models keep working on the plan.

All product surfaces (claude.ai, Desktop, Mobile, Claude Code, Cowork) share these limits.

## 2. Per-plan rules for Fable 5 / 5.1

| plan | Fable | per-model line in `/usage`? |
|---|---|---|
| Free | not available | — |
| Pro | **not included**; usage credits only | no (this skill was built on Pro, hence the two-line output) |
| Max 5x, Max 20x | included up to 50% of weekly; then credits or switch model | yes (`Current week (Fable)`) |
| Team standard seat | credits only | no |
| Team premium seat | included up to 50% of weekly | yes |
| Enterprise seat-based, standard | credits only, if org enabled credits | no |
| Enterprise seat-based, premium | included up to 50% of weekly | yes |
| Enterprise usage-based | standard API rates | n/a |

Claude Code needs v2.1.255+ for Fable 5.1. The client also knows a `Current week (Sonnet only)`
row (shown when `seven_day_sonnet` is present on max/team) and `seven_day_opus` for the older
Opus-family cap, so the per-model line can be any of Opus, Sonnet or Fable depending on plan and date.

## 3. Credits: three different things

1. **Usage credits** (a.k.a. extra usage / overage). Pay-as-you-go at API rates once plan limits are
   hit. Pro, Max 5x, Max 20x can enable; Team/Enterprise via admin. Monthly spend limit, auto-reload,
   $2,000/day redemption cap. Applies to Claude Code. The claude.ai page states: "Promotional credits
   are used before purchased credits", so **promotional credits are a sub-balance of usage credits**,
   not a separate limit. Usage bundles ($50/$250/$1000 prepaid, 10–30% off) top up the same balance.
2. **Cloud session credits.** An included credit that "applies automatically to cloud sessions. After
   it's used or expires, your plan's regular usage applies." On this account: $103 of $250 left,
   expires 7:59 AM GMT, November 5. This is the bucket the mobile app and the CLI text do not show.
   In the cached API response it appears under an obfuscated key (`iguana_necktie`) with
   `limit_dollars: 250`, `used_dollars: 146.87`, `utilization: 58.7`. The 2.1.288 client has no
   renderer for it; it does know a sibling `cinder_cove` rendered as "Claude Code and Cowork credit ·
   One-time credit · Expires <date>".
3. **Limit resets.** A one-time reset grant shown on the usage page under "Limit resets" with an
   expiry. None on this account right now.

Two entitlement checks also depend on credits, independent of quota: 1M-token context
(`long_context_credits_required`, "Usage credits required for 1M context") and any model that runs
on credits for the account (`model_requires_usage_credits`, e.g. Fable on Pro, or Fable past the 50%
sub-cap on Max).

### What "weekly 100% but requests still succeed" means

The API's per-response `overageStatus` is `allowed` / `allowed_warning` when "paid extra usage
covers the overflow (nothing will be cut off)" and `rejected` at hard exhaustion. So:

- credits enabled and funded ⇒ work continues, billed at API rates (promotional balance first);
- credits toggled on but balance £0 ⇒ the client records `extra_usage.is_enabled: false,
  disabled_reason: "out_of_credits"` ⇒ hard stop at 100%;
- credits off ⇒ hard stop at 100%.

This account today: toggle ON, balance £0, no spend limit, auto-reload off ⇒ **out_of_credits ⇒
hard stop when the week hits 100%** (cloud session credits only cover cloud sessions). The WARNING's
"either credits or a grace window" wording can now be made definitive when the cache is readable.

## 4. What the skill can read, headless

| source | documented? | what it gives | gaps |
|---|---|---|---|
| `claude -p "/usage"` text | semi (command documented, format not) | auth-mode line, session, weekly, per-model lines | no credits, no tier, no binding-limit flag; interactive-only credit rows are dropped in headless render |
| Claude Code's config file in the home directory → `cachedUsageUtilization` | **no** (internal cache, refreshed by every `/usage` run; `fetchedAtMs`) | `five_hour`, `seven_day`, `seven_day_opus/sonnet/oauth_apps/cowork`, `limits[]` (kind, percent, severity normal/warning, resets_at, scope, **is_active** = the binding limit), `extra_usage` (is_enabled, disabled_reason, used_credits, monthly_limit, currency), `spend` (balance, cap, auto_reload, can_purchase_credits), cloud credit bucket, `seven_day_breakdown` by product | obfuscated keys for promotional/cloud buckets; shape may change without notice |
| Claude Code's config file in the home directory → `oauthAccount` | no | `organizationRateLimitTier` = `default_claude_max_5x`, `organizationType` = `claude_max`, `hasExtraUsageEnabled`, `billingType` | tier string is an internal id |
| status line JSON (`rate_limits`) | **yes** | `five_hour`, `seven_day`, gateway `spend_limit` | interactive only; no per-model, no credits |
| API response headers (`anthropic-ratelimit-unified-*`) | internal | per-request status, overageStatus | not reachable from a skill |

## 5. Recommendations for the skill

1. **Keep the text parse as primary** (it is what `/usage` prints and what the eval graders check),
   and **add best-effort enrichment from the cache** after running `/usage`, only when
   `fetchedAtMs` is within ~2 minutes. Everything from the cache is labelled best-effort and the
   script must degrade silently to the three lines when the cache is missing or malformed.
2. New output lines (proposed):
   - `Plan: Max 5x` from `organizationRateLimitTier` (map `default_claude_pro`, `default_claude_max_5x`,
     `default_claude_max_20x`, `claude_team`, `claude_enterprise`; print the raw id if unmapped).
   - `Binding limit: weekly (all models) 89%` from the `limits[]` entry with `is_active: true`.
   - `Usage credits: ON but out of credits (balance £0.00)` | `ON · £X used of £Y monthly limit` |
     `OFF`, from `extra_usage` + `spend`. At weekly 100% this turns the WARNING into a definitive
     statement: "work will stop" vs "work continues on credits at API rates".
   - `Cloud session credit: $103 of $250 left · expires Nov 5 (cloud sessions only)` when a
     dollar-denominated bucket is present (any top-level key with `limit_dollars` that is not
     `five_hour`/`seven_day`). Do not name the obfuscated key.
3. **Interpretation rule for the per-model line**, in SKILL.md: the Fable (or Opus/Sonnet) line is a
   sub-cap of the weekly pool. Report it when it is the binding limit (`is_active`) or above 90%;
   otherwise mention it briefly. Never treat Fable room as capacity if session or weekly is exhausted.
4. **Plan-aware wording**: on Pro / standard seats there is no Fable line and Fable always bills
   credits; say so if the model in use is Fable and the tier is Pro.
5. **Fixtures**: add `max5x-fable.txt` (current three-line shape), `pro-two-line.txt`, a
   `max-sonnet-only.txt` shape, plus a `cached-usage-max5x.json` sample (scrubbed) for the enrichment
   tests. Team/Enterprise shapes are untested; mark them so.
6. **Eval**: add a pasted case where weekly is 100% and the cache says `out_of_credits`, expecting the
   reply to say work will stop at the next request rather than "may continue on credits".

Known unknowns: whether `is_active` means "most constraining" or "currently enforced" (observed:
true on the highest-percentage limit); whether promotional credits ever appear as a separate bucket
in the cache (none on this account to observe); Team/Enterprise `/usage` text shapes.

## 6. Wrap-up allowance (added 2026-10-04)

Source: https://support.claude.com/en/articles/17040437-claude-code-wrap-up-allowance. If Claude Code
hits the five-hour limit partway through a response, it may keep working briefly to reach a stopping
point. Available on Pro, Max and Team premium seats, Claude Code 2.1.277 or later; not for API key or
third-party cloud use. Pro: up to once per weekly period. Max and Team premium: each time a five-hour
limit is reached, within the weekly limit. It applies only to a response already in progress; new
messages after the limit do not get it. It counts toward the weekly limit. With usage credits on, the
allowance is used first, then credits.

Banners found in 2.1.289: "Usage limit reached · wrapping up" and, with credits on, "Usage limit
reached · brief included wrap-up, then usage credits". The allowance is not shown in `/usage` or in the
usage cache, so the skill infers eligibility from version, tier and session percent (80% or more).

## Sources

- Claude Fable models on your plan — https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan
- What is the Max plan? — https://support.claude.com/en/articles/11049741-what-is-the-max-plan
- Manage usage credits for paid Claude plans — https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans
- Buy usage bundles — https://support.claude.com/en/articles/14246112-buy-usage-bundles
- How do usage and length limits work? — https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work
- Claude Code error reference (usage limits section) — https://code.claude.com/docs/en/errors
- Claude Code status line (`rate_limits` schema) — https://code.claude.com/docs/en/statusline
- Local evidence: `claude -p "/usage"` on 2.1.288; Claude Code's config file in the home directory keys `cachedUsageUtilization`,
  `oauthAccount`, `cachedExtraUsageDisabledReason`; strings in the 2.1.288 binary; claude.ai Settings > Usage.
