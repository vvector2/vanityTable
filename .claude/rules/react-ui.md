---
paths:
  - "ui/**"
---

# React UI

- Mobile first: design for a phone screen, with large tap targets for accept and reject.
- Views: "to review" (`new`), accepted, rejected. Every decision can be undone.
- Each card shows the photo, price, title and a link to OLX. Accepted listings that have expired show an "expired" label.
- Always show the last successful sync time so a broken sync is noticeable.
- Keep dependencies minimal. No UI framework unless the user asks for one.
- UI text is in Polish.
