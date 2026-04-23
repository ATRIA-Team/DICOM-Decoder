import Foundation
import QuartzCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A display-link-based timer for accurate frame synchronization during cine playback.
/// Uses CADisplayLink on supported platforms to align frame ticks with the screen refresh rate.
internal final class CineTimer {
    private var displayLink: CADisplayLink?
    private let onTick: () -> Void
    private let frameRate: Double
    
    private var lastTickTime: CFTimeInterval = 0
    private let frameInterval: CFTimeInterval
    
    /// Initializes a new timer.
    /// - Parameters:
    ///   - frameRate: The desired playback frame rate in frames per second.
    ///   - onTick: Closure executed when a frame should be displayed.
    init(frameRate: Double, onTick: @escaping () -> Void) {
        self.frameRate = frameRate > 0 ? frameRate : 30.0
        self.frameInterval = 1.0 / self.frameRate
        self.onTick = onTick
    }
    
    /// Check if the timer is currently running.
    var isRunning: Bool { displayLink != nil }
    
    /// Starts the timer.
    func start() {
        guard !isRunning else { return }
        
        lastTickTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(handleTick))
        
        if #available(macOS 12.0, iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: Float(frameRate),
                maximum: Float(frameRate),
                preferred: Float(frameRate)
            )
        }
        
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    
    /// Stops the timer.
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func handleTick(displayLink: CADisplayLink) {
        let currentTime = displayLink.timestamp
        if currentTime - lastTickTime >= frameInterval {
            lastTickTime = currentTime
            onTick()
        }
    }
}
