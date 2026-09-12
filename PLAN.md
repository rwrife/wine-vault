# Wine Vault — PLAN

## Scope

An offline-first iPhone app for tracking a home wine collection (inventory,
photos, notes, drink-by windows) with an opt-in online price-lookup feature
that produces dated, sourced valuation quotes and a collection total. iOS is
the required primary platform, built against the **iOS 26 SDK or newer**.
Android is an explicitly deferred optional secondary.

## Architecture

```
┌──────────────────────────────────────────────┐
│ SwiftUI views                                │
│  Browse (list/filter) · Detail · Add/Edit    │
│  Valuation · Dashboards · Settings/Backup    │
│  Adaptive: compact = 1-col, regular = 2-col  │
│  (browser + persistent detail — the          │
│   iPhone Duo spanned layout migration target)│
├──────────────────────────────────────────────┤
│ View models (Observation)                    │
├──────────────────────────────────────────────┤
│ Domain layer (pure Swift)                    │
│  Bottle · ValuationQuote · DrinkBy window    │
│  Collection totals (pure functions, tested)  │
├──────────────────────────────────────────────┤
│ Data layer                                   │
│  SQLite (GRDB) store · app-private photo     │
│  library · CSV/ZIP exporters                 │
├──────────────────────────────────────────────┤
│ Valuation service (opt-in, injectable mock)  │
│  Query builder → HTTPS price provider        │
│  Quote cache w/ date + source provenance     │
└──────────────────────────────────────────────┘
```

## Technology choices

| Choice | Rationale |
|---|---|
| Swift + SwiftUI, iOS 26 SDK | Required primary platform; size-class adaptation gives the browser/detail split that later maps to the Duo second screen |
| GRDB (SQLite) | Local-first, relational, queryable for dashboards; single-file DB simplifies ZIP backup |
| App-private photo storage | Keeps photos with the app container for backup integrity; no Photo Library permission needed |
| Injectable `PriceProviding` protocol | Network is a plugin behind a protocol; deterministic mock tests; graceful offline degradation |
| GitHub Actions + App Store Connect API | Existing tool-lab ASC secret convention for archive/upload to TestFlight |
| Optional local AI later, off by default | Any AI assist (e.g. label text hints) must degrade to manual entry; not in MVP |

## Milestones & dependency order

1. **M1 Skeleton + CI** — Xcode project, iOS 26 SDK pin, CI build/test,
   lint. Everything depends on this.
2. **M2 Domain + persistence** — Bottle model, GRDB store, migrations,
   unit tests. Depends on M1.
3. **M3 Core workflow UI** — add/browse/edit/delete, photo capture, search,
   filters. Depends on M2.
4. **M4 Price lookup + valuation** — `PriceProviding`, quote provenance
   model, per-bottle and collection totals, clear "estimate" labeling.
   Depends on M2 (can parallel M3 after API stub).
5. **M5 Dashboards + reminders + adaptive layout** — charts, drink-by
   notifications, regular-width two-column layout. Depends on M3/M4.
6. **M6 Export/backup/restore + privacy hardening** — CSV, ZIP
   (DB + photos), restore flow, permission audit. Depends on M2–M4.
7. **M7 TestFlight release** — signing via ASC secrets, privacy manifest,
   App Store metadata. Depends on all.

## Testing strategy

- Domain layer: pure-function unit tests (valuation math, date windows,
  totals) — no mocks needed.
- Persistence: in-memory SQLite round-trip tests, migration tests.
- Valuation service: protocol mock with canned/fixture responses; no live
  network in CI. Error paths: timeout, no-result, ambiguous match.
- UI: XCUITest smoke flows (add → browse → filter → export).
- Release gate: `xcodebuild` on iOS 26 simulator in CI.

## Packaging / distribution

- Ad-hoc & archive builds in CI.
- TestFlight upload via App Store Connect API using repo secrets
  `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` (names only).
- Bundle ID `com.infinityball.winevault` (registered in ASC).
- App Store later; privacy "data not collected" posture documented in the
  privacy manifest.

## iPhone Duo migration path

Build today with size-class-adaptive layouts: compact width = stacked
navigation; regular width = persistent two-column browser/detail. When Apple
ships dual-screen APIs, map the regular-width detail column onto the second
display and add fold/unfold scene continuity — a view-layer refactor only,
with the domain/data layers untouched. The dual-screen experience stays a
documented design target until the SDK supports it; no unavailable fold APIs
are depended on.

## Risks

- **Price-provider terms/coverage:** lookup needs a provider whose terms
  allow per-bottle reference quotes; MVP designs the protocol so the
  provider is swappable, and offline manual price entry is the fallback.
- **Label identification ambiguity:** no cloud OCR in MVP; user confirms
  any typed/pasted name. Mispriced matches are surfaced with provenance.
- **Valuation expectation management:** quotes are estimates with dates;
  UI language is locked down in acceptance criteria.
- **Dual-screen SDK timing:** mitigated by the adaptive-layout-first plan.

## Explicit non-goals

Accounts/cloud sync; marketplace/buying; social features; OCR cloud
services; AI pairing advice in MVP; Android in MVP; any health guidance on
alcohol; legal/tax advice on collection value.
