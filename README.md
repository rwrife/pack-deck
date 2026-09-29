# Pack Deck

Local-first iPhone trip-packing planner: reusable gear kits, deterministic quantity math from trip length and laundry access, and a persistent packing-progress control surface — no accounts, no cloud.

## Overview

Pack Deck helps travelers avoid overpacking and forgetting essentials. Users define reusable kits (carry-on tech, weekender clothes, baby gear, trail kit), build trips from those kits, and track packing progress as an append-only ledger of item states (`planned`, `packed`, `missing`, `omitted`, `unknown`).

The app is in early build-out. The repository now carries the native Swift
project skeleton — `PackDeck.xcodeproj` (app target `PackDeck`), the pure
domain package `Packages/PackDeckKit`, and the persistence package
`Packages/PackDeckStore` — plus the CI policy gates described under
"Platform contract". Domain logic, persistence, and UI land in later
milestones (see "Current status and milestones").

## Motivation

Most packing apps are account-centric, subscription-heavy, or opaque in how quantities are suggested. Travelers need a private tool that works offline, explains every recommendation, and can be trusted when network access is poor.

## Target users

- Frequent personal travelers who want fast, repeatable packing.
- Families or couples sharing practical checklists without cloud lock-in.
- Travelers with recurring contexts (business trip, gym trip, toddler travel, hiking weekend).
- Users who prefer explicit local data ownership and exports.

## End-to-end workflow

1. Create reusable kit templates with item counts and optional category tags.
2. Create a trip with destination context, duration, laundry access, and activity tags.
3. Build a trip packing list from one or more kits plus ad-hoc items.
4. Review deterministic quantity recommendations with named reasons.
5. Mark each item packed/missing/omitted during real prep.
6. Export a JSON backup and CSV checklist summary through Files share sheet.
7. Reuse the finished trip as a future template.

## MVP features

- Kit library with user-defined items, units, and optional category tags.
- Trip model with duration, laundry cadence, climate/activity hints (manual inputs only).
- Deterministic quantity engine with explainable outputs and unknown-safe behavior.
- Packing-progress state machine per item with timestamped transition ledger.
- Search/filter by status, kit, category, and missing-only views.
- Versioned local backup/restore (JSON) and checklist export (CSV).
- Accessibility baseline: Dynamic Type, VoiceOver labels, high-contrast status indicators, minimum hit targets.
- `PackWorkspaceLayout` seam for future iPhone Duo dual-screen adaptation.

## iPhone Duo design target

Future dual-screen mode keeps one screen as a persistent packing control surface (status counts + quick actions) while the other presents list detail, item notes, and recommendation explanations. Fold/unfold transitions must preserve selection and in-progress edits.

Current build shape is a standard native iPhone app. Native iPad support is disabled by default. No unavailable fold APIs are required. When Apple ships supported dual-screen APIs, `PackWorkspaceLayout` will map pane geometry and continuity behavior without changing domain or storage layers.

## Platform contract

- Native Swift (SwiftUI/UIKit) only.
- iPhone-only on iOS, with `TARGETED_DEVICE_FAMILY = 1` in all app-target configurations.
- iOS 26 SDK or newer is required.
- Android and native iPad support are out of scope unless explicitly requested.
- Bundle identifier / `PRODUCT_BUNDLE_IDENTIFIER`: `com.infinityball.packdeck`.
- App Store Connect bundle registration outcome: `CREATED com.infinityball.packdeck`.

## Privacy, permissions, and storage

- All user data is local-first in app storage.
- No accounts, cloud sync, ads, analytics SDKs, trackers, or remote inference in MVP.
- Optional local notifications for packing reminders are user-controlled.
- Files access is user-initiated for import/export only.
- No contacts, location, microphone, camera, or background tracking required for MVP.

## Non-goals

- No booking engine, flight/hotel aggregation, itinerary scraping, or email parsing.
- No social sharing feed, public profile, or collaborative cloud workspace.
- No automatic weather scraping dependency; optional weather hints are user-entered unless future explicit integration is added.
- No Android or native iPad release scope without explicit opt-in.
- No Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, or any cross-platform/hybrid framework.

## Current status and milestones

- ✅ Repository, topics, and iOS App Store Connect secrets configured.
- ✅ Bundle ID registered in App Store Connect.
- ✅ README/PLAN/toolchain scaffold committed.
- ✅ M1: Native Swift project skeleton (`PackDeck.xcodeproj`, `PackDeckKit`, `PackDeckStore`) + iPhone-only + toolchain pin + zero-network + native-only CI policy gates (issue #1).
- ✅ M2: Domain model, kit/trip models, and deterministic recommendation engine (issue #2).
- 🔜 M3: PackDeckStore persistence — GRDB schema, migrations, versioned backup (issue #3).
- 🔜 M4: Kit library UI — create, edit, and reuse packing kit templates (issue #4).
- 🔜 M5: Trip builder and packing workspace UI (issue #5).
- 🔜 M6: Export/import — JSON backup and CSV checklist export (issue #6).
- 🔜 M7: Accessibility and interaction QA pass (issue #7).

## Development quickstart

1. Install Xcode 26.0.1 (or newer with iOS 26+ SDK), Swift 6 toolchain (exact pin in `toolchain.json`).
2. Open `PackDeck.xcodeproj` in Xcode or run the Swift package tests:
   ```bash
   swift test --package-path Packages/PackDeckKit
   swift test --package-path Packages/PackDeckStore
   ```
3. Run the zero-network and native-only gates locally:
   ```bash
   bash scripts/check_zero_network.sh
   bash scripts/check_native_only.sh
   ```
4. Verify the iPhone-only build in CI on `macos-26` runner (asserts `TARGETED_DEVICE_FAMILY = 1` pre- and post-build, bundle id `com.infinityball.packdeck`, and privacy manifest embedding).

## App Store / signing plan

GitHub Actions repository secrets are configured (names only):

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_KEY_P8`
- `ASC_TEAM_ID`

Release automation must use these secret names for App Store Connect authentication, signing/provisioning, and TestFlight upload evidence.

## License

MIT
