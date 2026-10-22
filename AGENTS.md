# Narratix — Rules for AI Agents

## Project

Narratix = open-source audiobook player for **iOS + watchOS** (Swift), forked from BookPlayer (upstream: https://github.com/TortugaPower/BookPlayer, default branch `develop`). Handles offline audio playback, background/lock-screen playback, cloud sync, auth, media-server integrations (Jellyfin, AudiobookShelf) + Hardcover reading-progress sync, and paid entitlements (RevenueCat tiers: free / plus / lite / pro). The highest-severity defect surfaces are **memory/concurrency, player & AVAudioSession lifecycle, thread-correct persistence, and auth/entitlement handling**.

**License:** GPL-3.0. Upstream `LICENSE` and copyright headers must be preserved — GPLv3 does not permit stripping attribution. Never remove upstream copyright, and never strip monetization: RevenueCat subscription tiers are the product, not upstream slop.

**Scope:** Single `BookPlayer.xcodeproj` (no `Package.swift`, no `.xcworkspace`) — 9 native targets: iOS app, `BookPlayerKit` + `BookPlayerWatchKit` frameworks, watch app, phone + watch widgets, share extension, unit-test + UI-test bundles.

## Ground Truth (read first)

- **`CLAUDE.md`** (repo root, ~825 lines) is the **architecture & conventions ground truth** — read it before touching code. It is loaded by the automated PR reviewer (`.github/workflows/claude-review.yml` + `.github/claude/review-guide.md`); a stale claim there becomes a bad review. When you change an invariant it describes, update it in the same PR.
- **`AGENTS.md`** (this file) is the workflow/rules layer — verification policy, .devin orchestration, brand/fork constraints.
- `CONTRIBUTING.md`, `.github/PULL_REQUEST_TEMPLATE.md`, `.swiftlint.yml`, `.swiftformat` — upstream-owned process/style configs. Respect them; don't hand-police what tools own.

## How It Works (domain constraints — read before touching the code)

- **Real app source lives under `BookPlayer/`**: `Player/`, `Settings/`, `Profile/`, `Library/`, `Search/`, `Import/`, `Loading/`, `SecondOnboarding/`, `Coordinators/`, `Services/`, `Utils/`, `AppIntents/`, `Jellyfin/`, `AudiobookShelf/`, `Hardcover/`, `MediaServerIntegration/`. (Note: `CLAUDE.md` says "nested `BookPlayer/BookPlayer/`" — that claim is stale; the app folder sits directly at repo root.)
- **`BookPlayerKit`/`BookPlayerWatchKit` compile the top-level `Shared/` folder.** Every file in `Shared/` has **two** `PBXBuildFile` entries (iOS + watchOS) — adding to only one target breaks the watch build. `Shared/` must never import app-layer types.
- **Legacy trap:** `CLAUDE.md` still describes top-level `Player/`, `Services/`, `Coordinators/`, `Library/` stub dirs — they no longer exist at repo root; if feature-named dirs ever (re)appear at top level, never add files there. `BookPlayer/RootViewController.swift` is dead code (references missing base classes) — ignore it.
- **Architecture:** hybrid UIKit-coordinators (boot: `AppDelegate` → `SceneDelegate` → `LoadingCoordinator` → `MainCoordinator` → SwiftUI `MainView` TabView) + SwiftUI MVVM (`@MainActor` VMs next to their views, `BPTransition<Routes>` navigation). The `SceneDelegate → LoadingCoordinator → MainCoordinator` strong-retain chain must never be severed.
- **DI:** `AppServices.shared` → `CoreServices` struct of exactly 12 services, **two-step `init()` + `setup(...)`** pattern. SwiftUI gets services via `.environmentObject`/`.environment(\.key)` — each `@Entry` default is a non-functional placeholder. App Intents resolve through `AppDependencyManager` (extensions) or `awaitCoreServices()` (app).
- **Persistence is TWO stores:** CoreData (library — `Shared/CoreData/`, manual staged migrations v1…v12, store in the **App Group** container, no merge policy → write conflicts crash) and SwiftData (sync task queue — `Shared/SwiftData/`, store in app-support dir, versioned `SchemaV1→V3`, `SyncQueueRepository: ModelActor` is the only accessor). Never pass `NSManagedObject`s across contexts — use the `Simple*`/`Playable*` snapshots.
- **Sync engine:** `SyncQueueService` lanes (`sync` serial, `uploadFile` + provider lanes concurrent), S3 multipart uploads (64 MiB parts), parking on coded failures, entitlements gate server lanes (`pro`/`lite` only). Bearer token from Keychain per request — **never attach it to S3/presigned/third-party URLs** (`useKeychain: false`).
- **Player:** `PlayerManager` (~1500 lines, highest-risk file) — exactly one `AVPlayer`, recreated on reset/failure; every `currentItem` reassignment must be followed by `bindPlayableChapterSubscription`; AVAudioSession activate-on-play / delayed-deactivate; `MPRemoteCommandCenter` wired once; `SleepTimer` singleton.
- **Secrets:** `BuildConfiguration/*.xcconfig` → `Info.plist` `$(BP_*)` → `Configuration.swift` (`try!` — missing key crashes at launch). New secrets go through **template + `ci_scripts` + `Info.plist` + `ConfigurationKeys`** in lockstep, never inlined.
- **~26 `.lproj` locale dirs** (24 translated), themes via `Themeable` + `Shared/Styleguide`, SiriKit `INPlayMediaIntent` for playback suggestions + App Intents (sleep timer, widgets). Notification names cross process boundaries — renames break Watch/CarPlay.

## Tech Stack & Conventions (do not fight it)

- **Xcode 27.1 required** (iOS 27 SDK APIs + `ArrangementView` won't compile on earlier). Language mode is **Swift 5** (`SWIFT_VERSION = 5.0`, no strict-concurrency flag — actor isolation is review-enforced convention; don't bump ad hoc). Deployment targets: iOS **26.0**, watchOS **10.0**. iOS-only APIs in `Shared/` need `#if os(iOS)`/availability guards (they compile for watchOS too).
- **SPM deps are declared inside `project.pbxproj`** — no `Package.swift`. RevenueCat ~5.78, Sentry **exact 8.36.0**, Kingfisher ~8.10, JellyfinAPI ~1.0, plus Get, MarqueeLabel, DeviceKit, IDZSwiftCommonCrypto, Themeable, ZipArchive, DirectoryWatcher, BrowserDrop. `BlurHashDecode.swift` is vendored.
- **Lint/format are tool-owned — never flag what they own:** SwiftLint (build-phase run script; `line_length`, `file_length`, `force_try`, etc. disabled) + SwiftFormat (`.swiftformat`, 4-space — a second `.swift-format` config disagrees on indent; don't flag indentation). `try!` is allowed except on untrusted/remote/decoded data.
- **Sourcery is manual** (not a build phase); `Generated/AutoMockable.generated.swift` output is committed.
- **Commits:** Conventional Commits (`type(scope): description`). Work branches off `develop`; PRs target `develop`.
- **Upstream sync:** we track upstream `develop`. Treat app/`Shared/` internals as upstream-owned — prefer additive changes over invasive refactors so future upstream merges stay cheap.
- **Brand identity:** Narratix naming/branding is a **planned phase** (CI-verified), never ad hoc. Until then upstream names, bundle ids, and `BP_*` keys stay as-is.

## Build / Verify

```bash
# CI only — .github/workflows/ci.yml (push to main/develop, PRs to develop):
#   runner xcode-27 → xcode-select Xcode_27.1 → cp Debug.template.xcconfig Debug.xcconfig
#   → xcodebuild -resolvePackageDependencies
#   → xcodebuild -scheme BookPlayer -configuration Debug
#       -destination "platform=iOS Simulator,name=iPhone 17" build-for-testing
#   → test-without-building -testPlan "Unit Tests" -only-testing:BookPlayerTests
```

**Remote-first verification (mandatory):** this workspace is **Windows — we do NOT build or test locally.** There is no Xcode here; local work is edit-only with static review while iterating. Push the branch and let GitHub Actions verify — a CI green check counts as the gate. `scripts/release-check/` runs locally on a maintainer's Mac before release tags, never in CI; release builds come from Xcode Cloud (`ci_scripts/`, secrets via Xcode Cloud env vars).

**No secret-dependent jobs:** CI builds/tests unsigned on the simulator — never add workflow steps needing signing certs, App Store Connect keys, or backend credentials until a Release phase provisions them.

## Removed on Purpose — Do NOT Re-add

- Nothing stripped yet — the fork is a clean upstream checkout. Do not remove upstream copyright, license, terms files, or RevenueCat/BookPlayer-Pro monetization (GPLv3 + the product's business model).
- Realm is gone upstream (→ SwiftData). `DataManager.getSyncTasksRealmURL()` is dead code; don't reintroduce Realm.
- SiriKit custom intents were replaced by App Intents — don't add NEW `.intentdefinition` entries, but **keep the existing tracked `BookPlayer/Intents.intentdefinition`** (its PlayMedia `mediaContainer`-only combination is the opt-in for `INPlayMediaIntent` media suggestions — deleting it silently kills Siri/lock-screen suggestions).

## Gotchas

- **No local build safety net** — grep all references (`project.pbxproj`, entitlements, `Info.plist`, `.xcconfig`, workflows, `ci_scripts`, imports) before deleting or renaming anything.
- **`Debug.xcconfig` is untracked and holds real prod secrets — never commit it.** `Release.xcconfig` is tracked with `replace.me` placeholders and rewritten by `ci_post_clone.sh` on Xcode Cloud.
- **Two formatters disagree** (`.swiftformat` 4-space vs `.swift-format` 2-space) — never flag indentation width.
- **CoreData migrations are manual and staged** — a model change needs all 5 steps (new model version + `DBVersion` case + mapping model + post-migration population + bundled resources). `saveContext` `fatalError`s on failure; no merge policy.
- **Windows checkout:** Unix-isms (symlinks, case-sensitive paths, `ci_scripts` shebangs) can be hostile; avoid `git clean -fdx`. File writes should use forward-compatible line endings.
- **GPLv3:** third-party deps must stay GPL-compatible; no proprietary SDK additions.

## Agent Guidelines & Workflow (this repo's .devin system)

### Resource Discipline (mandatory, non-trivial tasks)
Before any non-trivial task:
1. Read `docs/toolset.md` intent-map (task type → resources)
2. Invoke every skill + sub-agent in that row
3. Read every rule for that task type (`.devin/rules/`)
4. At task end: `code-reviewer` sub-agent on final diff (non-negotiable)
5. Append learnings via `/ce-compound` if durable lesson

Phase implementations follow `.devin/prompt/phase.md`; quick tasks follow `.devin/prompt/quick.md` + `.devin/prompt/rules.md`. Skip all this for single-line edits, pure Q&A, reading files.

### Project-Type Filter (native iOS/watchOS Swift app)
Per `docs/toolset.md` intent-map:
- **Skip irrelevant:** css-architect (no CSS), pwa-engineer (native app), web-scraper, design-cloner (not cloning a site), monorepo-manager (single `.xcodeproj`, not a monorepo), email-engineer (no email surface), seo-specialist (deferred — ASO phase if we ship to the App Store).
- **Keep universal:** code-reviewer, debugger, test-engineer, security-auditor, performance-engineer, git-master, migration-specialist, docs-writer, build-optimizer, devops-engineer, dx-optimizer, caveman-compressor, vibe-coding-auditor.
- **Keep domain-fit:** media-optimizer (audio pipeline = core), i18n-specialist (~26 locales), animation-engineer, design-system-builder (SwiftUI + Themeable tokens), content-writer, frontend-designer (SwiftUI design taste, anti-slop), backend-architect, state-manager (@Observable/Combine/environment DI), database-engineer (CoreData + SwiftData dual-store), file-handler (import/upload pipeline = core), search-architect (library search), realtime-engineer (WatchConnectivity, background sessions, Live Activities), payment-integrator (RevenueCat subscriptions = core), type-safety-engineer (Swift 6 concurrency/Sendable), a11y-specialist (VoiceOver is a shipped feature), analytics-engineer (Sentry, privacy-first only), pixel-analyst, researcher.
- **Quality gates:** CI-only — SwiftLint (build phase) + build-for-testing + BookPlayerTests unit suite on GitHub Actions. No local builds.

## Communication Style

Default **caveman-lite** (lightly compressed, readable, technically accurate). `/caveman` skill for full/ultra/wenyan modes.

## Key References

> `docs/` is the private knowledge layer — **fully gitignored**, local workspace only. `CLAUDE.md` and upstream docs are tracked.

- `docs/toolset.md` — intent map (task type → skills, sub-agents, rules)
- `docs/plan.md` — phased plan + status
- `docs/project.md` — project state/structure
- `docs/tools-log.md` — .devin resources invoked per session
- `docs/CONCEPTS.md` — project vocabulary
- `docs/research.md` — research, ADRs, gotchas, open questions
- `docs/idea.md` — competitive analysis + Feature Gap List
- `docs/design/design-system.md` — UI tokens + rules
- `CLAUDE.md` — tracked upstream architecture ground truth
