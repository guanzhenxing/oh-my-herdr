# Changes

This mod is the app mod shipped with [DnzzL/herdr-automations](https://github.com/DnzzL/herdr-automations)
(MIT, see `THIRD_PARTY.md` at the repository root); `mod.json` was adapted (dialog placement and
title), and `main.js` carries the two local patches listed below. Its CLI is vendored in
`cli/herdr-automations/` at the repository root.

- 2026-11-14: config/state folder watchers no longer die on their first failure — a
  failed watch backs off (1s doubling to 60s) and retries, and watchers re-arm from
  `refresh` as the paths become known, so a CLI installed after the mod loaded starts
  pushing updates without a reload.
- 2026-11-14: a missing `herdr-automations` CLI now shows a usable message ("install it with
  install.sh…") instead of the raw fork/exec error the panel used to print.
