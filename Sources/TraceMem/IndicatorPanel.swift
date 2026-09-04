import AppKit

/// Floating, non-activating pill at bottom-center: mic level + partial transcript.
@MainActor
final class IndicatorPanel {
    private let panel: NSPanel
    private let levelBar = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "")
    private var timer: Timer?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 64),
                        styleMask: [.nonactivatingPanel, .borderless, .hudWindow], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let bg = NSVisualEffectView(frame: panel.contentView!.bounds)
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 16
        bg.layer?.masksToBounds = true
        bg.autoresizingMask = [.width, .height]
        panel.contentView = bg

        levelBar.style = .bar
        levelBar.isIndeterminate = false
        levelBar.minValue = 0
        levelBar.maxValue = 1
        levelBar.frame = NSRect(x: 16, y: 44, width: 388, height: 8)
        bg.addSubview(levelBar)

        label.frame = NSRect(x: 16, y: 10, width: 388, height: 30)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingHead
        label.maximumNumberOfLines = 2
        label.cell?.truncatesLastVisibleLine = true
        bg.addSubview(label)
    }

    func show(status: String, level: @escaping @MainActor () -> Float?) {
        label.stringValue = status
        levelBar.doubleValue = 0
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.minY + 48))
        }
        panel.orderFrontRegardless()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [levelBar] _ in
            MainActor.assumeIsolated {
                // averagePowerLevel is dB (≈ -60 silence … 0 loud); map to 0…1
                let db = level() ?? -60
                levelBar.doubleValue = max(0, min(1, Double(db + 50) / 50))
            }
        }
    }

    func update(text: String) {
        label.stringValue = text.isEmpty ? "…" : text
    }

    func hide() {
        timer?.invalidate(); timer = nil
        panel.orderOut(nil)
    }
}
