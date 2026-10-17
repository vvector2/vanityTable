# Toaletka: MVP Requirements and Plan

Date: 2026-10-17 | Status: requirements gathered, technology not chosen, OLX data spike pending

## 1. Goal

The app searches OLX for retro and vintage vanity tables ("toaletka") on the user's behalf and shows only the listings that meet the criteria. She just browses and decides: **accept** or **reject**.

## 2. MVP scope

- One searched product (vanity table), one source (OLX), one user.
- Sync with OLX every 30 minutes.
- A list of matching listings she has not yet reviewed.
- Remembering decisions: accepted or rejected.

**Out of MVP:** price filter, location, notifications (push, email), other marketplaces, multiple products, accounts and login, retro/vintage style detection.

## 3. Matching criteria

A listing matches when it meets all three conditions:

1. The title or description contains a word similar to "toaletka" (**fuzzy search**).
2. The listing is active.
3. It has at least one photo.

### Fuzzy search

- Covers inflected forms ("toaletki", "toaletkę", "toaletce"), typos ("toaleka", "totaletka"), missing Polish diacritics and letter-case differences.
- Title and description are split into individual words, and each word is compared against the pattern "toaletka".
- **The similarity threshold is determined empirically during testing.** It must be a configuration value, not hard-coded.
- An exceptions list (e.g. "toaleta", "toaletowy") lives in configuration and is extended after the first results.
- Initially let more through rather than less: a false listing costs one "reject" click, a missed vanity table costs much more.
- **The match score (similarity value) is stored with the listing**, so the threshold can be tuned on facts.

### Price decisions

- The price criterion (ranges, rules for "free" and listings without a price) is **removed from the MVP**.
- Price is still stored as a separate numeric field and displayed on the listing. Adding a filter later is cheap.

## 4. Listing lifecycle

`new` → `accepted` or `rejected`, plus an `expired` flag when the listing disappears from OLX.

- A listing is identified by its OLX ID, so it does not reappear after the next sync.
- A rejected listing does not come back, even if the ad is edited.
- Decisions can be changed (accept or reject can be undone).
- An accepted listing that expired stays in accepted, with a visible "expired" label.

## 5. Functional requirements

1. Periodic fetching of listings from OLX every 30 minutes.
2. Storing a listing: ID, title, description, price (number), link, photos, status, match score, dates (first seen and last sync).
3. Filtering by the criteria in section 3.
4. "To review" view: new matching listings with photo, price, title and a link to OLX.
5. Actions: accept and reject.
6. Accepted view and optionally a rejected view, with the ability to change a decision.
7. Display of the last successful sync time.

## 6. Non-functional requirements

- A sync failure does not corrupt data or lose decisions.
- **Resilience to source failure:** a fetch error does not delete listings or mark them as expired.
- Works well on a phone.
- Low maintenance cost (private project).
- The data source is isolated behind an adapter (the app only knows the concept of a "listing"), so it can be replaced.

## 7. Access to OLX data

### Official API

- OLX has a public partner API, used mainly to publish and manage one's own listings and messages. It requires registering an application and obtaining OAuth client credentials.
- No endpoint for searching other users' listings was found in the reviewed documentation (not 100% ruled out, as the documentation loaded only partially).
- According to a February 2026 report, an application for monitoring listings was rejected at registration in the developer portal for suggesting "Data Scraping/Competitor Monitoring". **We assume the API is not available for this use case.**

### Fetching public pages (adopted as the source)

- Technically feasible; open-source OLX scrapers exist.
- No specific clause about automated fetching was found in the OLX terms of service, and robots.txt was not checked.
- OLX has sued in India over scraping as a breach of its terms (different jurisdiction, but it shows the company's attitude).
- Risks: IP blocks or captcha, layout changes, legal risk (the author's assessment, not legal advice).
- **We knowingly accept that scraping may be unreliable.**

### Fetching rules

- One request every 30 minutes, a reasonable User-Agent, no parallelism.
- Stop on a 429 error or captcha; no circumventing protections.
- Fallback plan: OLX's built-in saved search with notifications.

## 8. Risks and inconsistencies to resolve

### Need a decision (depend on the spike result)

1. **Fuzzy search vs. the query sent to OLX.** If we ask OLX for "toaletka", it will not return listings with a typo, so our fuzzy search never sees them. Options: a narrow query with fuzzy as a supplement, or a broader candidate set (e.g. the whole furniture category with pagination) filtered on our side, at the cost of more requests and a higher blocking risk.
2. **The description is usually not in the results list.** Searching the description requires opening each listing page. Proposal: fetch the description only for new, unknown listings.
3. **Listing activity.** Determine whether the list shows only active listings or whether status must be checked on the listing page.

### Other

- **No notifications** weaken the point of a 30-minute sync: the MVP's value is filtering and decision memory, not reaction speed.
- **The photo criterion** will filter out little, since almost every listing has a photo (unless we detect placeholder images).
- **False "expired".** A listing should be considered expired only after a successful sync in which it is missing, or after confirmation on its own page.
- **Where it runs.** A job every 30 minutes needs an always-on environment. Requests from data centers are blocked more often than from a home connection. This affects the technology choice.
- **Rejected listings do not return**, even after a price drop or a re-listing with a new ID. Proposal: store the price at the moment of rejection.
- **Synonyms** ("komoda z lustrem", "psyche", "stolik kosmetyczny") are not caught by fuzzy search, so omissions are possible.
- **Duplicates.** Sellers re-post the same listing with a new ID.
- **Match quality.** The word "toaletka" alone will also catch modern furniture, while retro and vintage is what she wants. Later: highlighting words like "retro", "vintage", "PRL", "lata 60".
- **First run** will bring in hundreds of existing listings at once. To decide: all go to review, or sort by newest.
- **Data and photos.** Store photo links, not copies, and do not collect seller data. Downside: a photo may disappear after the listing expires.
- **Access.** Without login, anyone who knows the app address can see the list and click decisions. Simple protection (e.g. a password) is needed.

## 9. MVP success criterion (proposal)

After a week, most listings on the list are sensible (few rejections for "this is not a vanity table"), and a manual check on OLX finds no listings the app missed.

## 10. Next steps

1. **Spike (separate task, not started):** check what the OLX search page returns: what is in the results list versus only on the listing page, how pagination works, how an inactive listing is marked, plus robots.txt.
2. Based on the spike, resolve points 1 to 3 in section 8.
3. Sketch the data model and the sync flow.
4. Choose the technology (last).
