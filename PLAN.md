# Pack Deck Plan

## Scope

Build a native Swift iPhone-only app that keeps trip packing private, deterministic, and offline-first. MVP supports one user on one device, with reusable kits, explainable recommendation math, and explicit packing-progress tracking.

## Architecture

### 1) Domain layer (`Packages/PackDeckKit`)

Pure Swift module (Foundation-only) for deterministic logic:

- `KitTemplate`
- `KitItem`
- `Trip`
- `TripItem`
- `Recommendation`
- `PackTransition`
- `PackSummary`

Rules:

- Append-only item-state transition ledger.
- Recommendation engine must emit reasons and uncertainty markers.
- Unknown-safe semantics: missing trip context downgrades certainty, never fabricated confidence.
- Deterministic outputs from identical inputs.

### 2) Persistence layer (`Packages/PackDeckStore`)

- SQLite via GRDB in app container.
- Versioned migrations with fixture tests.
- Transactional mutation boundaries around trip/item updates.
- Versioned backup codec (JSON) and export codec (CSV).

### 3) App layer (`PackDeck`)

SwiftUI-first with focused UIKit bridges as needed.

Primary surfaces:

1. Kit library and kit editor.
2. Trip creation and context inputs.
3. Packing workspace (item list + quick status actions + recommendation reason view).
4. Progress dashboard and unresolved/missing filter.
5. Import/export and privacy controls.

`PackWorkspaceLayout` is the only future dual-screen seam for iPhone Duo migration.

## Technology choices

- **Swift 6 + SwiftUI/UIKit:** required native iOS stack.
- **iOS 26+ SDK:** policy requirement and release baseline.
- **GRDB + SQLite:** reliable local-first persistence and schema migration support.
- **Swift Testing + XCTest + XCUITest:** deterministic domain, integration, and UI verification.

## Platform and policy constraints

- iPhone-only default: `TARGETED_DEVICE_FAMILY = 1` (never `1,2`).
- Native iPad support disabled unless explicit opt-in is provided.
- Android out of scope.
- Prohibited frameworks: Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity.
- Bundle ID must remain `com.infinityball.packdeck` across project config, Info.plist, signing, and CI.

## Milestones and dependency order

### M1 — Native scaffold + CI policy gates

- [x] Create Xcode project and package modules (`PackDeck.xcodeproj`, `PackDeckKit`, `PackDeckStore`).
- [x] Enforce iPhone-only build settings (`TARGETED_DEVICE_FAMILY = 1`) and bundle ID policy (`com.infinityball.packdeck`).
- [x] Add CI checks for native-only framework policy, zero-network empty-allowlist gate, and iOS 26+ toolchain contract.

### M2 — Domain engine

- Implement kit/trip/item models.
- Build deterministic recommendation engine with reason codes.
- Add domain tests for quantity math and unknown-safe behavior.

### M3 — Persistence + migrations

- Implement GRDB schema and repositories.
- Add migration tests and backup codec tests.

### M4 — Core workflow UI

- Build kit management, trip builder, and packing workspace.
- Add accessibility contracts and regression tests.

### M5 — Export/import and privacy controls

- JSON backup/restore with preview and transactional replace.
- CSV checklist export and data retention controls.

### M6 — Release path

- Implement signing/TestFlight automation using `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`.
- Produce real release evidence (build artifacts + processing state).

## Testing strategy

- Domain unit tests for recommendation and transition logic.
- Persistence integration tests for migrations and serialization.
- UI tests for primary pack workflow and accessibility identifiers.
- CI policy tests for iPhone-only family setting and prohibited framework checks.

## Packaging and distribution

- Internal TestFlight builds first.
- App Store release after MVP acceptance and privacy copy review.
- No Android or iPad release scope by default.

## Risks and mitigations

- **Over-scoping recommendation intelligence:** keep deterministic rule set before any advanced heuristics.
- **State drift during quick interactions:** enforce append-only transition ledger and transactional writes.
- **Policy regressions from regeneration/tools:** CI check for `TARGETED_DEVICE_FAMILY = 1` and bundle-ID prefix.
- **Dual-screen uncertainty:** isolate in `PackWorkspaceLayout` seam and defer until public APIs exist.

## Explicit non-goals

- No cloud accounts/subscriptions or tracker SDKs.
- No booking, itinerary email parsing, or OCR pipeline in MVP.
- No Android or native iPad implementation by default.
- No Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity.
