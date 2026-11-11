#if DEBUG
import QuartzCore
import UIKit

/// Testing aid: records frame times from creation until `summary()`, to
/// show whether an animation dropped frames.
@MainActor
final class FrameMonitor: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var gaps: [CFTimeInterval] = []
    private let created = CACurrentMediaTime()

    override init() {
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        if last > 0 { gaps.append(link.timestamp - last) }
        last = link.timestamp
    }

    func summary() -> String {
        link?.invalidate()
        link = nil
        let frame = 1.0 / Double(UIScreen.main.maximumFramesPerSecond)
        let slow = gaps.filter { $0 > frame * 1.5 }
        let worst = (gaps.max() ?? 0) * 1000
        let firstTick = gaps.first.map { _ in "" } ?? " (no frames)"
        return String(format: "worst frame %.0f ms, %d slow of %d frames, hitch time %.0f ms%@",
                      worst, slow.count, gaps.count,
                      slow.reduce(0) { $0 + $1 - frame } * 1000, firstTick)
    }
}
#endif
