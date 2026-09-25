# Testing guide

Wine Vault's permanent quality gate (issue #8). Everything here runs in CI
on every pull request and every push to `main`; this page is how you run the
same gates locally before pushing.

## What CI enforces

| Gate | Where | Rule |
|------|-------|------|
| Package tests + coverage | `ci.yml` → `packages` (ubuntu) | `swift test` with strict concurrency & warnings-as-errors; `WineVaultDomain` line coverage **≥ 90%** enforced by `Scripts/check_coverage_threshold.py`; every `Sources/` file must appear in the lcov trace (no silently untested files) |
| SwiftLint | `ci.yml` → `lint` | Domain + Data layers `--strict` (warnings fail); app targets baseline |
| iOS 26 build + tests | `ci.yml` → `build-test` (macOS, Xcode 26) | App builds with warnings-as-errors; unit tests + XCUITest core flows run on an iPhone simulator; regular-width two-column flows run on an iPad simulator; simulator bundle identity is asserted |

## Running everything locally

### Swift packages (Linux or macOS, no Xcode needed)

`WineVaultData` needs SQLite development headers. CI builds a pinned image
for exactly this:

```bash
docker build -f .github/docker/SwiftSQLite.Dockerfile -t wine-vault-swift:6.1-sqlite .

docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD:/src" -w /src/Packages/WineVaultDomain \
  wine-vault-swift:6.1-sqlite swift test

docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD:/src" -w /src/Packages/WineVaultData \
  wine-vault-swift:6.1-sqlite swift test
```

On macOS with a full Xcode install, plain `swift test` in each package
directory works too.

### Coverage gate (same numbers CI checks)

```bash
# from Packages/WineVaultDomain
swift test --enable-code-coverage
TEST_BINARY=$(find .build -type f -path '*debug/WineVaultDomainPackageTests.xctest' -print -quit)
llvm-cov export -format=lcov "$TEST_BINARY" \
  -instr-profile=.build/debug/codecov/default.profdata \
  -ignore-filename-regex='(.build|Tests)/' > /tmp/domain.lcov
python3 ../../Scripts/check_coverage_threshold.py /tmp/domain.lcov 90
```

(Use `xcrun llvm-cov ...` on macOS.)

### App unit tests + XCUITests (macOS only)

```bash
brew install xcodegen
xcodegen generate
xcodebuild test \
  -project WineVault.xcodeproj -scheme WineVault \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:WineVaultTests -only-testing:WineVaultUITests \
  CODE_SIGNING_ALLOWED=NO
```

Regular-width (iPad size-class) journeys:

```bash
xcodebuild test -project WineVault.xcodeproj -scheme WineVault \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=latest' \
  -only-testing:WineVaultUITests/WineVaultWorkflowUITests/testRegularWidthShowsBrowserAndDetailColumns \
  -only-testing:WineVaultUITests/WineVaultInsightsUITests/testRegularWidthTimelineSelectionKeepsPersistentDetail \
  CODE_SIGNING_ALLOWED=NO
```

### Lint

```bash
swiftlint --strict --config .swiftlint.yml \
  Packages/WineVaultDomain/Sources Packages/WineVaultDomain/Tests \
  Packages/WineVaultData/Sources Packages/WineVaultData/Tests
swiftlint --config .swiftlint.yml WineVault WineVaultTests WineVaultUITests
```

## UI-test launch seams

UI tests launch the app with flags; the app swaps in fully deterministic,
offline dependencies. Production launches never see any of this.

| Flag | Effect |
|------|--------|
| `--ui-testing` | Temporary on-device store; `InertBackupService`; `InertReminderScheduler`; fixture price provider |
| `--ui-testing-seed=wine-vault` | Seeds the fixed `uiTestSeedBottles` set (see `Packages/WineVaultDomain/Sources/WineVaultDomain/UITestSeed.swift`) |
| `--ui-testing-price=<ok\|no-results\|timeout\|disabled>` | Scripts `FixturePriceProvider` behavior |
| `--ui-testing-restore-file` | Adds the `stageRestoreButton` seam so the backup→restore journey can run without the unscribable system document picker |

## Adding fixtures

### Price-provider fixtures (Domain)

`FixturePriceProvider` is the only provider used in tests/CI — valuation
behavior is proven with zero network. Add a scenario by:

1. Extending `FixturePriceProvider.Behavior` if the transport outcome is new
   (keep it a transport-level outcome, not a UI concern), and
2. Asserting the path in `Packages/WineVaultDomain/Tests/WineVaultDomainTests/PriceProvidingTests.swift`,
   plus the app-level outcome in `WineVaultTests/ValuationFlowTests.swift`
   and (if user-visible) a UI-test launch flag.

The five mandated quote paths — no-result, timeout, ambiguous,
currency-mismatch, stale-quote — are asserted in `PriceProvidingTests`,
`ValuationTests`, and `ValuationFlowTests`. A new quote-shaped behavior
without an assertion in one of those files will not pass review.

### Persistence fixtures (Data)

Round-trip changes go through `SQLiteBottleRepository(inMemory:)` or a
temporary-file database. The fuzz harness
(`Packages/WineVaultData/Tests/WineVaultDataTests/SyntheticRoundTripTests.swift`)
generates 500 synthetic bottles from a **fixed seed** — if you add a field to
`Bottle`, extend `syntheticBottles(count:seed:)` so the fuzz corpus covers
it. Never introduce randomness without a fixed seed: a failing test must
reproduce byte-for-byte.

### Migration fixtures

New schema versions must keep the forward-migration test
(`testVersionOneDatabaseMigratesForwardAndPreservesBottle`) honest: it
reopens an older-version database file and asserts applied migrations and
data preservation.

### Seed UI data

Change `uiTestSeedBottles` only in lockstep with the UI tests that assert on
exact counts/groups (timeline, dashboard, coverage statements).

## Flaky-test policy

- No test is allowed to retry silently. `xcodebuild`/`swift test` run with
  no retry configuration in CI; a red test stays red.
- If a test is observed failing on an unchanged tree (verified by re-running
  the run against the same SHA), it is **quarantined within one cycle**:
  either fixed by the next executor run, or moved out of the gating job
  with a `// QUARANTINE(#issue)` marker and a linked GitHub issue created
  in the same PR that quarantines it.
- Quarantined tests must not be deleted; they stay runnable locally and
  are un-quarantined by the fix.
- Logging: every quarantine decision is recorded as a comment on the
  quarantine issue with the failing run URL and attempt count. No run
  counts and no issue link → the quarantine is invalid and the gate stays
  red.
