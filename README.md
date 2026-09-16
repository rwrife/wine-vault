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

The XcodeGen-driven app target retains its iOS 26 SDK requirement. The app now
provides the local add/browse/search/filter/edit/delete workflow over the GRDB
repository, with optional camera-only label capture into the existing private
photo store. Compact width uses stacked navigation and regular width keeps the
browser and detail visible. No networking, accounts, cloud, telemetry, Photo
Library permission, or secret access is used by this workflow.
Deletion is permanent after confirmation and also removes that bottle's
cascading valuation history; undo is intentionally not offered because it
could not faithfully restore those quotes. App-stack deletion also removes
private photo files that no remaining bottle references while preserving any
shared photo reference.

- [x] M0: README/PLAN, issue backlog, executor cron
- [ ] M1: project skeleton, CI, local data layer (source implemented; each PR's
  hosted iOS 26 CI gates acceptance)
- [x] M2: add/browse/edit bottles (source and tests implemented; hosted iOS
  evidence remains required as described below)
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
- Pure-domain logic lives in `Packages/WineVaultDomain`; run
  `cd Packages/WineVaultDomain && swift test`.
- GRDB persistence and private photo storage live in `Packages/WineVaultData`;
  Linux needs SQLite development headers, then run
  `cd Packages/WineVaultData && swift test`.
- Both package suites run in CI with Swift 6.1, strict concurrency,
  warnings-as-errors, and LLVM source coverage. Pull requests archive the
  `domain.lcov` and `data.lcov` artifacts produced by those runs after CI
  verifies an `SF` entry for every package source file.
- Native CI keeps build/test result bundles, raw logs, and bounded simulator
  diagnostics for 14 days, including failures.
- Lint: `swiftlint --strict --config .swiftlint.yml Packages/WineVaultDomain Packages/WineVaultData`
- Release path: GitHub Actions → App Store Connect API (secrets above) →
  TestFlight. See PLAN.md.

## Repository layout

```
project.yml                  XcodeGen spec (source of truth for the project)
Packages/WineVaultDomain/    Pure-domain Swift package (no iOS deps, Linux-testable)
Packages/WineVaultData/      GRDB repository, migrations, and private photo store
WineVault/                   App target
  App/                       Entry point
  Domain/ Data/ Services/    Layers (populated by later milestones)
  UI/                        SwiftUI views
WineVaultTests/              App-host unit tests
WineVaultUITests/            Add/list/search/edit/delete + adaptive UI tests
.github/workflows/ci.yml     Domain/Data (Linux) + coverage + lint + iOS 26 gate
```

## Local data architecture

`WineVaultDataStack.appPrivateDefault()` creates
`Library/Application Support/com.infinityball.winevault/vault.sqlite` and a
sibling `photos/` directory inside the app container. Database records store
only validated flat `photos/<filename>` references.
`WineVaultDataStack.savePhoto(_:fileExtension:for:)` atomically saves and
attaches a photo, while `garbageCollectOrphanPhotos()` reads repository
references and removes unreferenced files under the same exclusive coordinator.
All stack instances share a process-wide coordinator, including reopened vaults;
serializing independent roots is an intentional MVP tradeoff. Do not mix raw
standalone repository/photo-store access with a stack-owned storage root.
Stack-owned repository mutations validate every photo reference under that
coordinator. Raw photo deletion is disabled for stack-owned stores; use
`deletePhoto(_:from:)` to detach and conditionally remove a file atomically.
The root, photos directory, and initialized database file retain their captured
filesystem identities, which are rechecked before access so detectable
replacement fails closed while canonical ancestor symlinks remain supported.
GRDB is pinned exactly to 7.10.0 and migrates registered schemas forward (`v1`
inventory, then `v2` notes and cascading valuation quotes).

The storage root is app-private and exclusively owned by cooperating
`WineVaultDataStack` operations in this process. Callers must quiesce and close
the stack before an external restore or replacement of its files. The iOS
sandbox prevents other apps from changing them. Deliberate concurrent raw
filesystem mutation by a compromised process in the same sandbox is outside the
MVP contract; these path-based checks fail closed on detectable identity
replacement but do not claim to eliminate every hostile filesystem TOCTOU.

Collection count functions are pure throwing functions: they report
`CollectionSummaryError.quantityOverflow` instead of trapping if a total does
not fit in `Int`. `ValuationQuote` values are immutable and validate finite
nonnegative amounts plus nonblank currency, source, and query provenance during
both construction and decoding.

## Issue #3 acceptance evidence

| Acceptance item | Source/test status | Evidence status on this Linux worktree |
|---|---|---|
| Complete add/edit form, stepper, tags, inline labeled validation | Implemented; domain tests cover normalization, invalid fields, identity, and photo preservation | Domain tests runnable in Swift Docker |
| Optional camera, rationale, usage description, manual fallback, no Photo Library permission | Camera-only capture writes through `WineVaultDataStack.savePhoto`; denied/unavailable states keep the form usable | **BLOCKED-NOT-DONE:** needs a real device/simulator permission check |
| Browse fields, search, and region/grape/tag/drink-by filters | Implemented; domain tests cover search, composed filters, drink-by injection, and facets | Domain behavior is Linux-testable; rendered UI needs iOS evidence |
| Confirmed permanent deletion | Implemented; confirmation states that the bottle and cascading valuation history are deleted | **BLOCKED-NOT-DONE:** app-host execution needs Xcode 26 |
| Empty states, compact stack, regular split, Dynamic Type AX5, VoiceOver labels | Implemented with adaptive system SwiftUI controls and no fixed text sizes | **BLOCKED-NOT-DONE:** requires manual AX5/VoiceOver and size-class checks; no accessibility claim is made yet |
| XCUITest add → list → search → edit → delete | Added to `WineVaultUITests`, the generated scheme, and the iOS 26 CI invocation | **BLOCKED-NOT-DONE locally:** Linux has no Xcode/iOS simulator; hosted CI must provide evidence |

This matrix deliberately distinguishes implemented source from platform
verification. Camera, VoiceOver, AX5 layout, compact navigation, and the
regular-width split remain incomplete until real CI/device evidence is
recorded; Linux package success is not treated as substitute evidence.

## License

MIT
