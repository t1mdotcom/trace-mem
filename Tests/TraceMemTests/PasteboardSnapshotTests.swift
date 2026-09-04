import AppKit
import Testing
@testable import TraceMem

@Test func snapshotRestoresAllTypes() {
    let pb = NSPasteboard(name: NSPasteboard.Name("trace-mem-test-\(UUID())"))
    defer { pb.releaseGlobally() }
    let item = NSPasteboardItem()
    item.setString("hallo", forType: .string)
    item.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("dev.theinemann.blob"))
    pb.clearContents()
    pb.writeObjects([item])

    let snap = PasteboardSnapshot(pb)
    pb.clearContents()
    pb.setString("ersetzt", forType: .string)
    #expect(pb.string(forType: .string) == "ersetzt")

    snap.restore(to: pb)
    #expect(pb.string(forType: .string) == "hallo")
    #expect(pb.pasteboardItems?.first?.data(forType: NSPasteboard.PasteboardType("dev.theinemann.blob")) == Data([1, 2, 3]))
}

@Test func emptySnapshotRestoresEmpty() {
    let pb = NSPasteboard(name: NSPasteboard.Name("trace-mem-test-\(UUID())"))
    defer { pb.releaseGlobally() }
    pb.clearContents()
    let snap = PasteboardSnapshot(pb)
    pb.setString("x", forType: .string)
    snap.restore(to: pb)
    #expect(pb.pasteboardItems?.isEmpty ?? true)
}
