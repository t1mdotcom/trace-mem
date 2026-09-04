import Testing
@testable import TraceMem

private let builtIn = MicInfo(uid: "b", name: "MacBook Pro Mikrofon", isBuiltIn: true)
private let airpods = MicInfo(uid: "a", name: "AirPods", isBuiltIn: false)

@Test func prefersBuiltInWhenNoChoice() {
    #expect(MicSelection.pick(preferredUID: nil, from: [airpods, builtIn]) == builtIn)
}

@Test func honorsUserChoice() {
    #expect(MicSelection.pick(preferredUID: "a", from: [airpods, builtIn]) == airpods)
}

@Test func fallsBackWhenChoiceMissing() {
    #expect(MicSelection.pick(preferredUID: "gone", from: [airpods]) == airpods)
    #expect(MicSelection.pick(preferredUID: nil, from: []) == nil)
}
