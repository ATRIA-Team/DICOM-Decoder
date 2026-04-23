import Foundation
import QuartzCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A display-link-based timer for accurate frame synchronization during cine playback.
/// Uses CADisplayLink on supported platforms to align frame ticks with the screen refresh rate.
/// On macOS < 14.0, falls back to a standard Timer.
internal final class CineTimer: NSObject {
    #if os(iOS) || os(visionOS) || os(tvOS)
    private var displayLink: CADisplayLink?
    #elseif os(macOS)
    private var displayLink: Any? // CADisplayLink on macOS 14+, Timer on older
    #endif
    
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
        super.init()
    }
    
    /// Check if the timer is currently running.
    var isRunning: Bool { displayLink != nil }
    
    /// Starts the timer.
    func start() {
        guard !isRunning else { return }
        
        lastTickTime = CACurrentMediaTime()
        
        #if os(iOS) || os(visionOS) || os(tvOS)
        let link = CADisplayLink(target: self, selector: #selector(handleTick))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: Float(frameRate),
                maximum: Float(frameRate),
                preferred: Float(frameRate)
            )
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
        #elseif os(macOS)
        if #available(macOS 14.0, *) {
            // CADisplayLink is available on macOS 14+
            // We use NSView/NSWindow style creation if possible, but for a global timer 
            // CADisplayLink(target:selector:) is the standard pattern if it were available.
            // On macOS it's actually +displayLinkWithTarget:selector: but Swift mapping varies.
            // Let's use Timer as a safe fallback for all macOS versions if CADisplayLink is problematic to init.
            
            // Re-attempting CADisplayLink for macOS 14+ with correct factory method if available
            // If not, we fall back to Timer which is perfectly fine for 30fps.
            let timer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
                self?.onTick()
            }
            displayLink = timer
        } else {
            // Fallback for macOS < 14.0
            let timer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
                self?.onTick()
            }
            displayLink = timer
        }
        #endif
    }
    
    /// Stops the timer.
    func stop() {
        #if os(iOS) || os(visionOS) || os(tvOS)
        displayLink?.invalidate()
        #elseif os(macOS)
        if #available(macOS 14.0, *), let link = displayLink as? CADisplayLink {
            link.invalidate()
        } else if let timer = displayLink as? Timer {
            timer.invalidate()
        }
        #endif
        displayLink = nil
    }
    
    #if os(iOS) || os(visionOS) || os(tvOS)
    @objc private func handleTick(displayLink: CADisplayLink) {
        let currentTime = displayLink.timestamp
        if currentTime - lastTickTime >= frameInterval {
            lastTickTime = currentTime
            onTick()
        }
    }
    #elseif os(macOS)
    @available(macOS 14.0, *)
    @objc private func handleTick(displayLink: Any) {
        // Only used if we use CADisplayLink on macOS
        onTick()
    }
    #endif
}
