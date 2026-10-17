---
name: update-docs
description: Record a project decision or spike result in docs/mpv.md and docs/architecture.md, keeping both consistent. Use when the user settles an open item, finishes the OLX spike, or changes a requirement.
---

# Update project docs

1. Read `docs/mpv.md` and `docs/architecture.md` in full.
2. Restate the decision in one sentence and confirm it with the user if it is ambiguous.
3. Find every place it affects: decision tables, _(proposal)_ sections, "Open items", "Risks", "Next steps".
4. Edit both files:
   - move the item from open or proposal to decided, and drop the _(proposal)_ marker only where it is now agreed
   - update the `Date | Status` line to today
   - remove or rewrite text the decision makes obsolete; do not leave contradictions
5. Summarize what changed in each file.
