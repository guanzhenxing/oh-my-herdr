# Changes

This mod is Image Viewer from [dougcunha/herdr-mods](https://github.com/dougcunha/herdr-mods)
(MIT, see `THIRD_PARTY.md` at the repository root), vendored without other changes. Local patches:

- 2026-11-23 (upstream 3b89d24, "double the curly quotes in every PowerShell literal"):
  `quote` also doubles the curly quotes U+2018–U+201B — PowerShell treats them as single
  quotes, so a file or folder name carrying one could end a `'…'` literal the mod built
  and run code.
