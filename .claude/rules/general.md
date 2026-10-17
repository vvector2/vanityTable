# General rules

- `docs/mpv.md` and `docs/architecture.md` are the source of truth. If a change contradicts them, stop and say so instead of silently diverging.
- Sections marked _(proposal)_ in the docs are not agreed. Do not build on them as final without confirming with the user.
- Keep the MVP small. Price filters, notifications, accounts, multiple products and other marketplaces are out of scope.
- Low running cost matters: prefer pay-per-request and serverless options, and avoid always-on resources (e.g. NAT Gateway) unless the user agrees.
- Never store seller personal data. Store photo links, not copies.
- Code, comments, commit messages and docs are written in English. User-facing UI text is in Polish.
