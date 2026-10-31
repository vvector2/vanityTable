# Feature: Search Criteria (Saved Searches)

Date: 2026-10-31 | Status: agreed. `mpv.md` is an archive of the MVP and is not changed. The architecture side is in `architecture.md` sections 4 to 7; this file is the working spec for the feature.

## 1. Goal

The user creates searches for any product. Each search has its own **criteria** and its own list of listings to accept or reject. The toaletka search from the MVP becomes the first (seeded) search.

## 2. Scope

| In                                                              | Out (separate features)                                            |
| --------------------------------------------------------------- | ------------------------------------------------------------------ |
| Search as an entity: create, list, view, delete                 | AI chat that fills the criteria (this form is its target)          |
| Criteria edited with a plain form                               | Image similarity (`images` is not in the criteria yet)             |
| Listings scoped per search                                      | Sync scaling: queue, one request stream, cap on active searches    |
| Home screen with the list of searches                           | Notifications, other marketplaces, multiple users                  |
| Seeded toaletka search                                           | Editing, pausing and resuming a search (no `PUT` for now); per-search fuzzy threshold |

## 3. Terms

| Term          | Meaning                                                                      |
| ------------- | ---------------------------------------------------------------------------- |
| Search        | What the user creates: title, criteria, status (always `active` for now; pausing comes later). |
| Criteria      | The filter model inside a search.                                            |
| Seeded search | The toaletka search that exists from day one. Behaves exactly as the MVP.    |

## 4. Criteria model

| Field             | Type                         | Required | Notes                                                                   |
| ----------------- | ---------------------------- | -------- | ----------------------------------------------------------------------- |
| `keywords`        | string[]                     | yes      | At least one. Fuzzy-matched (`mpv.md` section 3).                       |
| `excludeKeywords` | string[]                     | no       | A listing containing one of these words is dropped.                     |
| `priceMin`        | number or null               | no       | PLN.                                                                    |
| `priceMax`        | number or null               | no       | PLN.                                                                    |
| `location`        | `{ city, radiusKm }` or null | no       | Structured, not free text.                                              |
| `description`     | string                       | no       | Free text (color, style, details). Displayed only; not used for matching until the AI feature. |

Example:

```json
{
  "keywords": ["toaletka", "psyche"],
  "excludeKeywords": ["toaleta"],
  "priceMin": null,
  "priceMax": 600,
  "location": { "city": "Warszawa", "radiusKm": 30 },
  "description": "Retro, jasne drewno, z lustrem"
}
```

### Validation

| Rule                                                         |
| ------------------------------------------------------------ |
| `title`: 1 to 80 characters                                  |
| `keywords`: 1 to 10 items, each 2 to 50 characters           |
| `excludeKeywords`: up to 10 items, each 2 to 50 characters   |
| `priceMin` and `priceMax`: 0 or more; `priceMin` <= `priceMax` when both are set |
| `radiusKm`: 0 or more; needs a `city`                        |
| `description`: up to 500 characters                          |

Errors use the existing `400 VALIDATION_ERROR` body.

## 5. Matching

- The criteria drive both the OLX query and the local filter. Price and location go to OLX where it supports them and are checked again locally.
- Every word in `keywords` is compared as in `mpv.md` section 3. The best score is stored as `match_score`.
- A listing with an `excludeKeywords` word is dropped.
- The fuzzy threshold and the exceptions list stay global configuration (SSM).
- Active and photo checks stay unchanged.
- The seeded search: `keywords = ["toaletka"]`, no price, no location.

## 6. Listings per search

- The status (`new`, `saved`, `rejected`) belongs to a search and listing pair. The same OLX ad in two searches has two independent statuses.
- Editing and pausing a search are not in this feature. To change the criteria, delete the search and create a new one.
- Deleting a search deletes its listings.

## 7. Data model

Details are in `architecture.md` section 4. In short:

- New table `Searches`: `id`, `userId`, `title`, `criteria`, `status`, `createdAt`, `updatedAt`; GSIs `userId-createdAt-index` and `status-createdAt-index`.
- `Listings`: new `searchId`; `id` = UUIDv5 of `searchId:sourceId`; new `searchStatus` = `<searchId>#<status>`; GSI `searchStatus-firstSeenAt-index` replaces `status-firstSeenAt-index`.

## 8. API

`llstingApi.md` is updated to match. `PUT /searches/{id}` is not needed now; it returns with edit and pause.

| Method | Path             | Description                                                    | Scope             |
| ------ | ---------------- | -------------------------------------------------------------- | ----------------- |
| GET    | `/searches`      | List searches with counts per status; optional `status` filter | `searches/read`   |
| POST   | `/searches`      | Create a search                                                | `searches/write`  |
| GET    | `/searches/{id}` | One search, for the criteria view                              | `searches/read`   |
| DELETE | `/searches/{id}` | Delete the search and its listings                             | `searches/write`  |

Changes to existing endpoints:

- `GET /listings` and `GET /listings/counts` take a required `searchId`.
- `POST /listings` takes `searchId`. `409` applies to the search and `sourceId` pair.
- The sync job reads active searches with `GET /searches?status=active` (scope `searches/read`).

DTOs:

- **CriteriaDto**: the fields in section 4.
- **SearchDto**: `id`, `title`, `criteria`, `status`, `counts` (`{ new, saved, rejected }`), `createdAt`, `updatedAt`.
- **CreateSearchRequest**: `title`, `criteria`. The API sets `id`, `userId` (from the token), `status=active` and the dates.

## 9. UI (user-facing text in Polish)

| Screen            | Content                                                                                              |
| ----------------- | ---------------------------------------------------------------------------------------------------- |
| Home              | "Moje wyszukiwania": one card per search with title, counts (new, saved, rejected); button "Nowe wyszukiwanie" |
| Search form       | Create only. Fields: Tytuł, Słowa kluczowe, Wykluczone słowa, Cena od, Cena do, Miasto, Promień (km), Opis. Buttons: Zapisz, Anuluj |
| Inside a search   | The existing New, Saved and Rejected tabs, scoped to the search; a read-only view of the criteria; button Usuń (with confirmation); link back to Home |

The chat on Home is a later feature; this form is what it will fill in.

## 10. Interim sync rule

Until the sync scaling feature, the sync Lambda scans the active searches one after another. With 15 s between pages a run can reach the Lambda 15-minute limit, so keep active searches at 3 or fewer.

## 11. Acceptance criteria

1. The user can create a search with only a title and one keyword; all other criteria are optional.
2. The user can view and delete a search.
3. The same OLX ad matching two searches appears in both, and accepting it in one does not change the other.
4. The sync job scans each active search with its own criteria.
5. A listing with an excluded word, or outside the price range, is not stored as `new`.
6. Home shows correct counts per search.
7. Invalid criteria are rejected with `400 VALIDATION_ERROR`.
