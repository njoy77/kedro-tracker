import Foundation
import Testing
@testable import Kedro

@Suite("Handle validation")
struct HandleValidationTests {
    @Test("Valid handles normalize like the API: trimmed, lowercased, no @")
    func normalizes() throws {
        let handle = try HandleValidation.validate("  @Noah.K ").get()
        #expect(handle.rawValue == "noah.k")
        #expect(handle.description == "@noah.k")
        #expect(try HandleValidation.validate("a_b").get().rawValue == "a_b")
        #expect(try HandleValidation.validate("12345678901234567890").get().rawValue.count == 20)
    }

    @Test("Each problem is reported", arguments: [
        ("", HandleProblem.empty),
        ("@", .empty),
        ("no", .tooShort),
        ("abcdefghijklmnopqrstu", .tooLong),
        ("noah k", .invalidCharacters),
        ("noah-k", .invalidCharacters),
        ("nøah", .invalidCharacters),
        ("🦊🦊🦊", .invalidCharacters),
    ])
    func problems(input: String, expected: HandleProblem) {
        #expect(HandleValidation.validate(input) == .failure(expected))
    }

    @Test("Invalid characters win over length, so the message is about what to fix")
    func characterProblemFirst() {
        #expect(HandleValidation.validate("a!") == .failure(.invalidCharacters))
    }

    @Test("Agrees with Handle(_:) on everything it accepts")
    func agreesWithDomain() {
        for input in ["noah", "@ANA.K", "x", "bad handle", "the.noah", "abcdefghijklmnopqrstuv", "ok_9"] {
            let validated = try? HandleValidation.validate(input).get()
            #expect(validated == Handle(input), "\(input)")
        }
    }

    @Test("Taken handles are refused")
    func taken() {
        #expect(HandleValidation.validate("@Noah", taken: ["noah"]) == .failure(.taken))
        #expect((try? HandleValidation.validate("noah.k", taken: ["noah"]).get())?.rawValue == "noah.k")
        // Format problems still come first.
        #expect(HandleValidation.validate("no", taken: ["no"]) == .failure(.tooShort))
    }

    @Test("Suggestions skip taken handles, best first")
    func suggestionsSkipTaken() {
        let free = HandleValidation.uniqueSuggestions(firstName: "Noah", taken: [])
        #expect(free.first?.rawValue == "noah")
        #expect(free.count == 3)

        let some = HandleValidation.uniqueSuggestions(firstName: "Noah", taken: ["noah", "noah.k"])
        #expect(!some.map(\.rawValue).contains("noah"))
        #expect(!some.map(\.rawValue).contains("noah.k"))
        #expect(some.count == 3)
    }

    @Test("Falls back to numbered handles when the usual ones are gone")
    func numberedFallback() {
        let usual = Set(Handle.suggestions(firstName: "Ana", count: 8).map(\.rawValue))
        let suggestions = HandleValidation.uniqueSuggestions(firstName: "Ana", taken: usual)
        #expect(suggestions.map(\.rawValue) == ["ana2", "ana4", "ana5"])
        #expect(suggestions.allSatisfy { !usual.contains($0.rawValue) })
    }

    @Test("Names with accents, spaces and short names still give valid handles")
    func awkwardNames() {
        #expect(HandleValidation.uniqueSuggestions(firstName: "Zoë", taken: []).first?.rawValue == "zoe")
        #expect(HandleValidation.uniqueSuggestions(firstName: "Jo", taken: []).first?.rawValue == "jox")
        #expect(HandleValidation.uniqueSuggestions(firstName: "Mary Kate", taken: []).first?.rawValue == "marykate")
        let long = HandleValidation.uniqueSuggestions(firstName: "Bartholomewxyzabcdefg", taken: [])
        #expect(long.allSatisfy { Handle.lengthRange.contains($0.rawValue.count) })
    }

    @Test("Every problem has a literal message")
    func messages() {
        let problems: [HandleProblem] = [.empty, .tooShort, .tooLong, .invalidCharacters, .taken]
        #expect(Set(problems.map(\.message)).count == problems.count)
        #expect(HandleProblem.tooShort.message.contains("3"))
        #expect(HandleProblem.tooLong.message.contains("20"))
    }

    @Test("Availability through the directory ignores your own handle")
    @MainActor
    func directoryAvailability() async throws {
        let store = InMemoryGameStore(operations: PreviewData.historyOperations)
        let directory = LocalPlayerDirectory(store: store) { PreviewData.noah.ref }
        let checker = DirectoryHandleAvailability(directory: directory)
        #expect(try await checker.isAvailable(PreviewData.ana.handle, for: PreviewData.noah.ref) == false)
        #expect(try await checker.isAvailable(PreviewData.ana.handle, for: PreviewData.ana.ref) == true)
        #expect(try await checker.isAvailable(Handle(constant: "nobody.here"), for: PreviewData.noah.ref) == true)
    }
}
