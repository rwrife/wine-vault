# Wine Vault

A local-first iPhone app that inventories a home wine collection — bottles,
quantities, vintage, region, photos, and drink-by notes — with an **optional
online price lookup** that values individual bottles and the whole collection.
No accounts, no cloud database, no subscription.

**Pitch:** Local-first iPhone app that inventories a home wine collection with
photos and notes, and an optional online price lookup to value individual
bottles and the whole collection — no accounts, no cloud.

## Motivation

Home collectors usually track wine in a spreadsheet or not at all. Existing
cellar apps bury data behind vendor accounts and cloud sync, and most free
ones can't tell you what your collection is worth. Wine Vault keeps every
record on-device, works fully offline, and treats price lookup as an opt-in
network feature: you ask for a valuation, it fetches a reference price for
that bottle, stores the quote with its date and source, and never phones home
otherwise.

## Target users

- Home wine collectors (10–500 bottles) who want ownership of their data
- Gift recipients and new collectors building a first cellar
- People tracking collection value for insurance or estate purposes
- Anyone who wants drink-by reminders without creating an online account

## Concrete use cases

1. **Shelf stock-up:** photograph a label, confirm the parsed name, set
   quantity and where it's stored — 20 seconds per bottle, fully offline.
2. **Holiday valuation:** select the collection (or a subset), tap
   "Estimate value"; each bottle gets a reference price with a dated quote
   and you get a collection total.
3. **What's ready to drink?** filter by drink-by window to see bottles in
   their suggested window now.
4. **Insurance snapshot:** export the full inventory with valuations as CSV
   and keep a receipt-photo archive in the ZIP backup.

## How to use (intended end-to-end workflow)

1. Add bottles: scan/photo a label, or type name + vintage + region +
   quantity + storage location.
2. Organize with free-form tags (region, grape, occasion, rack/shelf).
3. Optionally request price lookups per bottle or per collection; quotes are
   stored with date and source, clearly marked as estimates.
4. Review dashboards: bottles by region, value over time, drink-by timeline.
5. Export CSV / ZIP backup (including photos) anytime; restore on a new
   device from the same file.

## iPhone Duo dual-screen design target

The dual-screen value story: on the unfolded iPhone Duo, the collection
browser occupies the primary screen while the second screen acts as a
persistent detail/control surface — label photo, tasting notes, valuation
history, and drink-by actions stay visible while you scroll, sort, and edit
the list. Folded, the app is a normal one-handed list→detail flow; unfolding
restores the same session into the spanned layout without losing context.

**Build shape (SDK gap):** native dual-screen/foldable APIs are not yet
available, so Wine Vault ships today as a **standard iOS app with an
optional tablet/adaptive size-class layout** (regular-width two-column
browser + detail). The two-column adaptive layout is the migration target:
when dual-screen SDK support matures, the secondary column relocates to the
companion display with continuity across fold/unfold, without changing the
data layer or navigation model.

## MVP feature list

- Bottle records: name, producer, vintage, region, grape, quantity,
  storage location, photo(s), tasting notes, drink-by date
- Add via manual entry or photo capture (photo stored locally; no OCR cloud
  dependency in MVP)
- Search, filter (region/grape/drink-by/tag), and sort
- Optional online price lookup per bottle / per selection, with dated quote
  provenance and clearly-labeled estimated collection total
- Dashboards: count by region/grape, value timeline, drink-by timeline
- CSV export + ZIP backup/restore (photos included)
- Local notifications for drink-by reminders (opt-in)

## Non-goals

- No accounts, cloud sync, social features, or community pricing crowdsourcing
- No e-commerce, bottle buying/selling, or marketplace links-as-value
- No barcode/label OCR *service* dependence; no wine-news or review feed
- No sommelier/AI pairing advice in MVP; no medical/health guidance on
  alcohol consumption
- No Android build in MVP (iOS is the required primary platform)

## Privacy, permissions, and data storage

- **Data storage:** all records in an on-device SQLite database inside the
  app's private container; photos in app-private storage. Nothing leaves the
  device unless the user exports or explicitly requests a price lookup.
- **Permissions:** Camera (label photos) and Notifications (drink-by
  reminders) only — both opt-in, both gracefully degradable.
- **Network:** only price-lookup requests, initiated per-request by the
  user. Lookup requests carry only the query text the user chose to send;
  no device identifiers, no collection metadata in bulk.
- **Export/backup:** user-owned CSV/ZIP files via the system share sheet;
  no vendor-held copies.

## Bundle ID / App Store Connect

- Bundle identifier: `com.infinityball.winevault`
- App Store Connect registration: **CREATED** (registered 2026-09-12 via the
  App Store Connect API).
- CI signing/release uses the repository Actions secrets `ASC_KEY_ID`,
  `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` (names only; values live only
  in GitHub encrypted secrets).

## Current status and milestones

M1 skeleton in progress: XcodeGen-driven app target, iOS 26 SDK pin in
CI, Domain Swift package, CI build + test + lint gates. No store or
network code exists yet.

- [x] M0: README/PLAN, issue backlog, executor cron
- [ ] M1: project skeleton, CI, local data layer
- [ ] M2: add/browse/edit bottles (core workflow)
- [ ] M3: opt-in price lookup + collection valuation
- [ ] M4: dashboards, drink-by reminders, adaptive tablet layout
- [ ] M5: export/backup/restore, TestFlight release

## Development quickstart

The `.xcodeproj` is generated, not committed — one less merge-conflict
magnet. Requirements: Xcode 26+ (iOS 26 SDK or newer — required) and
`brew install xcodegen`.

```bash
brew install xcodegen        # one-time
xcodegen generate            # -> WineVault.xcodeproj
open WineVault.xcodeproj     # scheme: WineVault
```

- Unit tests: `xcodebuild test -project WineVault.xcodeproj -scheme WineVault -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'`
- Pure-domain logic lives in `Packages/WineVaultDomain` and also builds +
  tests on Linux: `cd Packages/WineVaultDomain && swift test`
- Lint: `swiftlint --strict --config .swiftlint.yml Packages/WineVaultDomain`
- Release path: GitHub Actions → App Store Connect API (secrets above) →
  TestFlight. See PLAN.md.

## Repository layout

```
project.yml                  XcodeGen spec (source of truth for the project)
Packages/WineVaultDomain/    Pure-domain Swift package (no iOS deps, Linux-testable)
WineVault/                   App target
  App/                       Entry point
  Domain/ Data/ Services/    Layers (populated by later milestones)
  UI/                        SwiftUI views
WineVaultTests/              App-host unit tests
.github/workflows/ci.yml     Domain (Linux) + lint + iOS 26 build/test gate
```

## License

MIT
