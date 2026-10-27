import Testing
@testable import Kedro

struct AppleSignInNonceTests {
    @Test func randomNonceHasRequestedLengthAndIsUnique() {
        let first = AppleSignInNonce.random(length: 32)
        let second = AppleSignInNonce.random(length: 32)
        #expect(first.count == 32)
        #expect(first != second)
    }

    @Test func hashesWithSHA256() {
        // Known SHA-256 of "abc".
        #expect(AppleSignInNonce(raw: "abc").hashed == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
