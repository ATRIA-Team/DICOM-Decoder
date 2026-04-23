import SwiftUI
import CoreGraphics

/// A complete playback interface for multi-frame Cine-Echocardiography loops.
/// Provides a scrubbable timeline, transport controls, and dynamic Metal-backed playback
/// via the `CinePlayerViewModel`.
@available(iOS 15.0, macOS 12.0, *)
public struct CinePlayerView: View {
    @StateObject private var viewModel: CinePlayerViewModel
    
    /// Initializes a new CinePlayerView.
    /// - Parameter viewModel: An active playback view model hooked to a loaded DICOM.
    public init(viewModel: CinePlayerViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Main image display bounding box
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let cgImage = viewModel.currentFrameImage {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .accessibilityLabel("Cine playback frame")
                        .accessibilityHint("Frame \(viewModel.currentFrameIndex + 1) of \(viewModel.totalFrames)")
                        .accessibilityAddTraits(.isImage)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
            // Control panel
            controlBar
        }
    }
    
    // MARK: - Subviews
    
    private var controlBar: some View {
        VStack(spacing: 12) {
            // 1. Scrub Slider
            HStack {
                Text("\(viewModel.currentFrameIndex + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)
                
                Slider(
                    value: Binding(
                        get: { Double(viewModel.currentFrameIndex) },
                        set: { newValue in
                            let target = Int(round(newValue))
                            if viewModel.currentFrameIndex != target {
                                viewModel.seek(to: target)
                            }
                        }
                    ),
                    in: 0...Double(max(0, viewModel.totalFrames - 1)),
                    step: 1.0
                ) { editing in
                    if editing {
                        viewModel.pause()
                    }
                }
                .accentColor(.blue)
                
                Text("\(viewModel.totalFrames)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .leading)
            }
            
            // 2. Transport Controls & Metadata
            ZStack {
                HStack(spacing: 32) {
                    Button(action: {
                        viewModel.pause()
                        viewModel.stepBackward()
                    }) {
                        Image(systemName: "backward.frame.fill")
                            .font(.title2)
                    }
                    
                    Button(action: {
                        if viewModel.isPlaying {
                            viewModel.pause()
                        } else {
                            viewModel.play()
                        }
                    }) {
                        Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                    }
                    
                    Button(action: {
                        viewModel.pause()
                        viewModel.stepForward()
                    }) {
                        Image(systemName: "forward.frame.fill")
                            .font(.title2)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.primary)
                
                // FPS Metadata anchored to trailing edge
                HStack {
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(String(format: "%.1f FPS", viewModel.frameRate))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(white: 0.1).ignoresSafeArea(edges: .bottom))
        .preferredColorScheme(.dark)
    }
}
