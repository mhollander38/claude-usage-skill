# Changelog

All notable changes to this plugin. Versions follow [Semantic Versioning](https://semver.org/).
The directory publishes from `main`; installed copies update only when `version` in
`.claude-plugin/plugin.json` changes, so every user-facing release bumps it and adds an entry here.

## [0.3.1] — unreleased

### Added
- Chat and Cowork behaviour: when live usage isn't available (no Claude Code CLI), the skill asks
  for the Settings → Usage figures or a screenshot and interprets them, instead of suggesting
  `/usage`, and does not run at task kickoff or step boundaries there.

### Changed
- Listing description mentions what the skill does outside Claude Code.

## [0.3.0] — 2026-10-04

First directory release.

### Added
- Plan, binding-limit, usage-credits and included-credit lines read best-effort from Claude Code's
  local usage cache (fresh, same account only; never prints personal fields).
- `Credits check:` line under the weekly WARNING saying whether work past 100% is billed, stops,
  or may draw on an included credit.
- Wrap-up allowance line (Claude Code 2.1.277+, Pro and Max, session at 80% or more, weekly below 100%).
- NOTICE at 95–99% weekly; decimal percentages handled.
- MIT license, listing icon, privacy policy, listing metadata.
- Eval cases for out-of-credits interpretation and relaying the script's Credits check line.

### Changed
- SKILL.md: per-model limits are sub-caps of the weekly pool; credits on with a zero balance is a
  hard stop; wider triggers (task kickoff, step boundaries, resume after reset, pasted output).

## [0.2.0] — 2026-10-03

### Added
- Standard plugin layout (`skills/check-usage/`, `.claude-plugin/plugin.json`).
- Plain-bash test suite with fixtures; `CHECK_USAGE_INPUT_FILE` and `CHECK_USAGE_CLAUDE_BIN` hooks.

### Fixed
- The script no longer fails silently: every failure prints a `check-usage:` line with a distinct
  exit code.

## [0.1.0]

### Added
- Initial `check-usage` skill: session and weekly usage with reset times, WARNING when the weekly
  quota is exhausted while the session shows room, usage-credits line relay.
