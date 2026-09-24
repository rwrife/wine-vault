# Wine Vault — Release Process (issue #7)

How a Wine Vault build gets from `main` to TestFlight, and what to do when it
doesn't. Secrets are named, never shown: `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_P8`, `ASC_TEAM_ID` live in repository Actions secrets and are
referenced only by name from `.github/workflows/release.yml`.

## Pipeline

`.github/workflows/release.yml` runs on any `v*` tag push (and can be run
manually via `workflow_dispatch`, with an optional upload toggle). It:

1. Pins the newest Xcode 26 on the runner and refuses to proceed without an
   iOS 26+ SDK.
2. Regenerates `WineVault.xcodeproj` from `project.yml` (xcodegen).
3. Creates an ephemeral keychain and archives `WineVault.xcarchive` for
   App Store distribution with **automatic signing**, authenticating to
   Apple with the App Store Connect API key
   (`-authenticationKeyPath/-ID/-IssuerID` + `-allowProvisioningUpdates`).
   The archive is verified in-step: bundle id must be
   `com.infinityball.winevault` and the embedded signature must pass
   `codesign --verify`.
4. Exports with `ExportOptions.plist` (`method: app-store-connect`,
   `destination: upload`) — the export itself uploads straight to App Store
   Connect over the same API key (Xcode 26 removed `altool`, so
   `-exportArchive … destination=upload` is the supported CLI path).
   The build number is the GitHub run number
   (`CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER`), which is monotonic across
   releases; `manageAppVersionAndBuildNumber: false` keeps the key from
   rewriting project state.
5. Generates the changelog from merged PRs since the previous tag
   (`Scripts/release_changelog.sh`) — squash-merge subjects carry the PR
   number, e.g. `feat: … (#14)`.
6. Polls the App Store Connect API until the build's `processingState` is
   `COMPLETE`, and prints the TestFlight **build id**, build version, and
   ASC app id — these go into the release notes / PR evidence.
7. On tag pushes, opens the matching GitHub release with the generated
   notes and the exported IPA.

## Cutting a release (v0.1.0)

```bash
# 1. Version bump (single place; validator enforces ReleaseInfo pairing)
#    project.yml -> MARKETING_VERSION
#    WineVault/App/ReleaseInfo.swift -> ReleaseInfo.version
git commit -am "chore: bump version to 0.1.0"

# 2. Tag and push — this triggers the pipeline
git tag -a v0.1.0 -m "Wine Vault 0.1.0"
git push origin v0.1.0
```

Watch the run: **Actions → Release → testflight**. A green run means the
build was uploaded *and* processed; the step output and the
`Await processed TestFlight build` log record the build id. Testers then
pick it up in TestFlight (internal group by default).

## Certificates & provisioning (automated handling)

- **Signing identity:** no `.p12` is stored. `-allowProvisioningUpdates`
  with the ASC API key lets `xcodebuild` request/create the distribution
  certificate through Apple's automation for the team in `ASC_TEAM_ID`. The
  hosted macOS runner's login keychain (pre-unlocked, codesigning partition
  preconfigured) receives the generated key/certificate; the workflow only
  logs identity *counts*, never names or key material.
- **Profiles:** App Store provisioning profiles are created/updated
  automatically for `com.infinityball.winevault` (registered in App Store
  Connect); nothing is committed to the repo.
- **Key hygiene:** `ASC_KEY_P8` is written to `$RUNNER_TEMP/asc/AuthKey.p8`
  (mode 600) and removed in an `always()` cleanup step. It is never echoed,
  never written to artifacts, and `export`/`archive` logs are piped through
  `xcbeautify` without dumping env.
- **Key role:** the ASC key needs App Manager or Admin to manage
  certificates/profiles and TestFlight metadata (Developer alone can upload
  but not manage).

## Retry & rollback

- **Retry an upload/processing failure:** fix the cause, bump the build
  number by re-running — push the tag again after a fresh commit, or run
  **Release → Run workflow** (`workflow_dispatch`) from the tag's commit;
  run-number-derived build numbers stay monotonic. `upload: false` gives a
  dry-run archive/export with no ASC submission.
- **Expire a bad TestFlight build:** App Store Connect → TestFlight →
  build → **Expire Build**. This stops testers from receiving it; it does
  not remove it from Apple's servers.
- **Rollback:** TestFlight has no "previous build" switch. Expire the bad
  build, revert/fix on `main`, and cut a new build (new run number).
  For a bad *version*, ship a fix-forward `0.1.1` tag — never delete tags.
- **Stale queued Actions run** (platform blip): cancel the run, re-dispatch
  the workflow; do not delete/recreate the tag.

## App Store metadata (draft state)

- `WineVault/App/ReleaseInfo.swift` is the single source of truth for
  store copy (title, subtitle, keywords, description, categories, privacy
  declaration, screenshot plan).
- `WineVault/AppStoreMetadata.plist` mirrors it for release tooling;
  `ReleaseMetadataTests` fails CI on drift, on store field-limit
  violations, on health/authoritative-price wording, and if
  `PrivacyInfo.xcprivacy` ever contradicts the "Data Not Collected"
  declaration.
- **Screenshots:** plan only (see `ReleaseInfo.screenshotPlan`) — capture
  each listed screen in the iOS 26 simulator at the listed pixel size before
  App Store submission; the iPad slot documents the shipped regular-width
  two-column layout (the documented iPhone Duo migration surface).

## Versioning rules

- `MARKETING_VERSION` (in `project.yml`) is the human version (`0.1.0`).
- Build number = GitHub Actions run number; do not reuse build numbers.
- Tags are `v<MARKETING_VERSION>` and the release notes are generated from
  the squash-merged PR subjects since the previous tag.
