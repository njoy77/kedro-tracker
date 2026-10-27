# AGENTS.md — iOS app

Rules for AI coding agents working on the Kedro iOS app.

## SwiftUI first, UIKit only as a last resort

- Build everything with **modern SwiftUI**.
- Use UIKit **if and only if** the feature cannot be built with SwiftUI. When that happens:
  - Wrap it in `UIViewRepresentable` / `UIViewControllerRepresentable` and keep the UIKit code as small as possible.
  - Add a comment explaining why SwiftUI could not do it.
- Do not use UIKit for convenience or out of habit (no `UIApplication`, `UIScreen`, `UIColor`, `UIHostingController`, or `UIAlertController` where a SwiftUI API exists).

## What "modern SwiftUI" means here

Prefer the newest API that the deployment target (iOS 26) supports:

| Use | Instead of |
|---|---|
| `@Observable` models, `@State` to own them, `@Environment(Model.self)` to read them, `@Bindable` for bindings | `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject` |
| `NavigationStack` with `navigationDestination(for:)` and value-based `NavigationLink` | `NavigationView`, destination-closure `NavigationLink` |
| `TabView` with the `Tab` API | `.tabItem` |
| `async`/`await`, `.task`, `AsyncSequence` | Combine, completion handlers, `onAppear` + `Task {}` |
| `ContentUnavailableView`, `#Preview`, `.sheet(item:)`, `.alert` with presented values | Custom empty states, `PreviewProvider`, boolean-only presentation |
| SwiftUI auth/system views (e.g. `SignInWithAppleButton`) | Their UIKit equivalents |
| Swift Testing (`import Testing`, `@Test`, `#expect`) | XCTest, except for UI tests |

## Swift and concurrency

- Swift 6 language mode with strict concurrency. The app target uses `MainActor` default isolation and approachable concurrency.
- Mark code that must run off the main actor `nonisolated` or `@concurrent` explicitly; keep types crossing actors `Sendable`.
- No force unwraps or `try!` outside tests and previews.

## Project layout

```
Kedro/
  App/        App entry point, root view, app-wide @Observable state
  Core/       Non-UI code: config, networking, auth
  Features/   One folder per feature (Games, Leaderboard, Players, …), views plus their models
KedroTests/   Swift Testing unit tests
Config/       Info.plist, entitlements, xcconfig files
```

- The Xcode project uses **folder-synchronized groups**: add files under `Kedro/` or `KedroTests/` and they are picked up automatically. Do not hand-edit `project.pbxproj` for new source files.
- Put build settings and secrets in `Config/*.xcconfig`. `Config/Secrets.xcconfig` is gitignored; `Config/Secrets.example.xcconfig` documents its keys.
- Every view gets a `#Preview`.

## Building and testing

From the repo root:

```bash
bun run ios:build
bun run --filter '@kedro/ios' test
```

Build output goes to Xcode's default DerivedData (outside the repo). Never pass `-derivedDataPath` pointing inside the repo; it lives in iCloud and code signing will fail.
