import Foundation
import SwiftUI
import CoreGraphics
import OSLog
import DicomCore

/// ViewModel responsible for managing Cine-Echocardiography playback state and rendering.
/// Coordinates a `DCMDecoder` with a `CineTimer` and `LRUCache` to deliver smooth, frame-indexed playback.
@MainActor
public final class CinePlayerViewModel: ObservableObject {
    /// The currently displayed frame index (0-based).
    @Published public private(set) var currentFrameIndex: Int = 0
    /// Whether the video is currently playing.
    @Published public private(set) var isPlaying: Bool = false
    /// The decoded uncompressed CGImage for the current frame.
    @Published public private(set) var currentFrameImage: CGImage?
    
    /// Total number of frames in the active sequence.
    public let totalFrames: Int
    /// Effective playback frame rate in FPS.
    public let frameRate: Double
    
    private let decoder: DCMDecoder
    private var frameCache: LRUCache<Int, CGImage>
    private var timer: CineTimer?
    private let logger = Logger(subsystem: "com.dicomswiftui", category: "CinePlayerViewModel")
    
    private let windowCenter: Double
    private let windowWidth: Double
    
    /// Initializes a new CinePlayerViewModel.
    /// - Parameter decoder: A loaded `DCMDecoder` containing multi-frame data.
    public init(decoder: DCMDecoder) {
        self.decoder = decoder
        self.totalFrames = decoder.numberOfFrames
        self.frameRate = decoder.derivedFrameRate
        
        // Cache capacity of ~10 frames prevents excessive memory usage while buffering
        self.frameCache = LRUCache(capacity: 10)
        
        let settings = decoder.windowSettingsV2
        if settings.isValid {
            self.windowCenter = settings.center
            self.windowWidth = settings.width
        } else {
            // Safe fallback defaults
            self.windowCenter = 127.5
            self.windowWidth = 255.0
        }
        
        logger.info("🎬 Initializing CinePlayerViewModel: \(self.totalFrames) frames @ \(self.frameRate) FPS")
        
        self.timer = CineTimer(frameRate: self.frameRate) { [weak self] in
            self?.stepForward(wrap: true)
        }
        
        // Load the initial frame synchronously if it's the only one, or async if larger.
        seek(to: 0)
    }
    
    deinit {
        timer?.stop()
    }
    
    /// Starts playback.
    public func play() {
        guard totalFrames > 1 else { return }
        isPlaying = true
        timer?.start()
    }
    
    /// Pauses playback.
    public func pause() {
        isPlaying = false
        timer?.stop()
    }
    
    /// Seeks to a specific frame and decodes it if necessary.
    /// - Parameter frameIndex: Target frame index (0 to totalFrames - 1).
    public func seek(to frameIndex: Int) {
        let safeIndex = max(0, min(frameIndex, totalFrames - 1))
        currentFrameIndex = safeIndex
        
        // Fast path: cache hit
        if let cached = frameCache.get(safeIndex) {
            currentFrameImage = cached
            return
        }
        
        // Slow path: offload rendering to background task
        Task {
            if let cgImage = await decodeAndRenderFrame(at: safeIndex) {
                frameCache.put(safeIndex, value: cgImage)
                // Ensure we only update the UI if the user hasn't scrubbed away while loading
                if self.currentFrameIndex == safeIndex {
                    self.currentFrameImage = cgImage
                }
            }
        }
    }
    
    /// Advances playback by one frame.
    /// - Parameter wrap: Whether to loop back to 0 when reaching the end.
    public func stepForward(wrap: Bool = false) {
        var next = currentFrameIndex + 1
        if next >= totalFrames {
            if wrap {
                next = 0
            } else {
                pause()
                return
            }
        }
        seek(to: next)
    }
    
    /// Reverses playback by one frame.
    public func stepBackward() {
        var prev = currentFrameIndex - 1
        if prev < 0 {
            prev = totalFrames - 1
        }
        seek(to: prev)
    }
    
    /// Background decoding operation. Uses the underlying DCMDecoder API.
    private nonisolated func decodeAndRenderFrame(at index: Int) async -> CGImage? {
        let bitDepth = decoder.bitDepth
        let width = decoder.width
        let height = decoder.height
        let spp = decoder.samplesPerPixel
        let center = self.windowCenter
        let winWidth = self.windowWidth
        
        return await Task.detached(priority: .userInitiated) { [decoder, center, winWidth, bitDepth, width, height, spp] in
            let cgImage: CGImage?
            
            if spp == 3 {
                // RGB / YBR color data (e.g. ultrasound, TEE)
                if let pixels24 = decoder.getPixels24(frame: index) {
                    cgImage = CGImageFactory.createRGBImage(from: pixels24, width: width, height: height)
                } else {
                    cgImage = nil
                }
            } else if bitDepth == 8 {
                if let pixels8 = decoder.getPixels8(frame: index) {
                    cgImage = CGImageFactory.createImage(from: pixels8, width: width, height: height)
                } else {
                    cgImage = nil
                }
            } else if bitDepth == 16 {
                if let pixels16 = decoder.getPixels16(frame: index) {
                    if let windowedData = DCMWindowingProcessor.applyWindowLevel(pixels16: pixels16, center: center, width: winWidth) {
                        let pixels8 = [UInt8](windowedData)
                        cgImage = CGImageFactory.createImage(from: pixels8, width: width, height: height)
                    } else {
                        cgImage = nil
                    }
                } else {
                    cgImage = nil
                }
            } else {
                cgImage = nil
            }
            return cgImage
        }.value
    }
}
