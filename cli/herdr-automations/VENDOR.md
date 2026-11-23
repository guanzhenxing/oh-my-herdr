# Vendored: herdr-automations

Upstream: <https://github.com/DnzzL/herdr-automations>, tag **v0.14.0** (commit `05e4629`),
MIT — © 2026 Thomas Legrand, its `LICENSE` is kept here. Pristine copy minus `.git`
(README, CHANGELOG, docs/ADR, skills and scripts included as shipped), with **two local
patches**:

- `internal/config/config.go` — `Save` used a bare `os.WriteFile`, while the panel's edit
  path (`write` in `internal/config/edit.go`) replaces the file through a rename exactly so
  a crash mid-write cannot leave truncated YAML. `Save` — the wizard's and the board pause
  toggle's writer — now goes through the same `write()`.
- `internal/daemon/state.go` — `scheduleState.save()` got the same rename treatment: a crash
  mid-write used to leave half a `schedule.json`, which the next start silently resets,
  dropping missed-run records in the gap.

To update: fetch the upstream tag, re-copy minus `.git`, re-apply the two patches, then
`go build ./... && go test ./...` and update the tag/commit here.

`install.sh` builds this directory with Go when one is on PATH; otherwise it downloads the
pinned upstream release binary and verifies its checksum.
