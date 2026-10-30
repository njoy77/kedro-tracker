import Foundation
import Testing
@testable import Kedro

/// Guards the navigation contract in `AppRoute`. SwiftUI fails these silently (the row highlights
/// and nothing pushes), so the tests read the app's sources:
/// - The tabs bind a typed `[AppRoute]` path, so a link or destination for any other value type on
///   a tab's stack never pushes (Learn's cards and drill, Settings → Edit Profile).
/// - A sheet that hosts Rules, the Knock Calculator or Learn needs `.appRouteDestinations()` inside
///   its own `NavigationStack`, or their links never push (the Table's "Why?" calculator).
@Suite("Navigation routes")
struct NavigationRouteTests {
    /// Views whose links are `AppRoute`s, so any stack hosting them must resolve `AppRoute`.
    private static let routeHosts = ["RulesSheet()", "KnockCalculatorView(", "LearnView()"]

    /// Stacks that own their own path and destinations, so may push their own value type.
    private static let ownStackRoutes: Set<String> = ["AppRoute", "Step"] // Step: OnboardingFlow

    private struct Source {
        let name: String
        let text: String
    }

    /// The app's Swift sources, or nil when the simulator can't read the host checkout.
    private static func appSources() -> [Source]? {
        let app = URL(filePath: #filePath)
            .deletingLastPathComponent() // Navigation
            .deletingLastPathComponent() // KedroTests
            .deletingLastPathComponent() // ios
            .appending(path: "Kedro")
        guard let files = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else { return nil }
        let sources = files.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .compactMap { url in
                (try? String(contentsOf: url, encoding: .utf8)).map { Source(name: url.lastPathComponent, text: $0) }
            }
        return sources.isEmpty ? nil : sources
    }

    @Test("Value-based links and destinations only use AppRoute (or a stack's own path type)")
    func linksUseAppRoute() {
        guard let sources = Self.appSources() else { return }
        for source in sources {
            for match in source.text.matches(of: /navigationDestination\(for: (\w+)\.self\)/) {
                let type = String(match.1)
                #expect(Self.ownStackRoutes.contains(type), "\(source.name) registers a destination for \(type); add an AppRoute case instead")
            }
            for match in source.text.matches(of: /NavigationLink\(value: ([A-Z]\w*)\./) {
                let type = String(match.1)
                #expect(Self.ownStackRoutes.contains(type), "\(source.name) links to a \(type); add an AppRoute case instead")
            }
        }
    }

    @Test("Every NavigationStack around Rules, the Knock Calculator or Learn resolves AppRoute")
    func routeHostsHaveDestinations() {
        guard let sources = Self.appSources() else { return }
        var checked = 0
        for source in sources where source.name != "AppRoute.swift" {
            for stack in Self.navigationStackBodies(in: source.text) where Self.routeHosts.contains(where: stack.contains) {
                checked += 1
                #expect(stack.contains(".appRouteDestinations()"), "\(source.name): NavigationStack { \(stack.prefix(80))… } needs .appRouteDestinations()")
            }
        }
        // The Table's Rules and "Why?" sheets, the rules sheet, onboarding's Learn sheet and previews.
        #expect(checked >= 6)
    }

    /// The text inside each `NavigationStack { … }` (or `NavigationStack(path:) { … }`), by brace matching.
    private static func navigationStackBodies(in text: String) -> [Substring] {
        var bodies: [Substring] = []
        var searchStart = text.startIndex
        while let stack = text[searchStart...].range(of: "NavigationStack") {
            searchStart = stack.upperBound
            guard let open = text[stack.upperBound...].firstIndex(of: "{"),
                  !text[stack.upperBound..<open].contains("\n") else { continue }
            var depth = 0
            var index = open
            while index < text.endIndex {
                if text[index] == "{" { depth += 1 }
                if text[index] == "}" {
                    depth -= 1
                    if depth == 0 { break }
                }
                index = text.index(after: index)
            }
            guard index < text.endIndex else { continue }
            bodies.append(text[text.index(after: open)..<index])
        }
        return bodies
    }
}
