import Testing
@testable import TraceMem

@Test func validateRejectsEmptyAndOversize() {
    #expect(Cleanup.validate(raw: "hallo welt", output: "  ") == .failure(.implausible))
    #expect(Cleanup.validate(raw: "hi", output: String(repeating: "x", count: 21)) == .failure(.implausible))
    #expect(Cleanup.validate(raw: "hallo welt", output: " Hallo Welt. ") == .success("Hallo Welt."))
}

@Test func timeoutFallsBack() async {
    do {
        _ = try await Cleanup.withTimeout(.milliseconds(50)) { try await Task.sleep(for: .seconds(5)); return "late" }
        Issue.record("expected timeout")
    } catch let f as Cleanup.Failure {
        #expect(f.description == "Timeout")
    } catch { Issue.record("wrong error \(error)") }
    let fast = try? await Cleanup.withTimeout(.seconds(1)) { "ok" }
    #expect(fast == "ok")
}

@Test func providerNoneReturnsRaw() async {
    var s = Settings(); s.provider = .none
    let r = await Cleanup.run("ähm hallo", settings: s)
    #expect(r.text == "ähm hallo" && r.failure == nil)
}

@Test func defaultProviderIsApple() {
    #expect(Settings().provider == .apple)
}
