//
//  MPRView.swift
//  DicomSwiftUI
//
//  Created by Gemini CLI.
//

import SwiftUI
import DicomCore

/// A SwiftUI view for Multi-Planar Reconstruction (MPR) display.
public struct MPRView: View {
    
    @ObservedObject var viewModel: MPRViewModel
    
    public init(viewModel: MPRViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                loadingView
            } else if let volume = viewModel.volume {
                mprGrid(volume: volume)
                controlsView(volume: volume)
            } else if let error = viewModel.error {
                errorView(error)
            } else {
                Text("No volume loaded")
                    .foregroundColor(.secondary)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
    
    // MARK: - Subviews
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
            Text("Assembling Volume...")
                .padding()
                .foregroundColor(.white)
        }
    }
    
    private func errorView(_ error: Error) -> some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.red)
            Text(error.localizedDescription)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding()
        }
    }
    
    private func mprGrid(volume: DicomSeriesVolume) -> some View {
        GeometryReader { geometry in
            let itemWidth = geometry.size.width / 2
            let itemHeight = geometry.size.height / 2
            
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Axial Plane
                    MPRPlaneView(
                        title: "Axial",
                        image: viewModel.axialImage,
                        index: $viewModel.axialIndex,
                        range: 0..<volume.depth,
                        aspectRatio: volume.spacing.x / volume.spacing.y,
                        onIndexChanged: { viewModel.updateAxialIndex($0) }
                    )
                    .frame(width: itemWidth, height: itemHeight)
                    
                    // Sagittal Plane
                    MPRPlaneView(
                        title: "Sagittal",
                        image: viewModel.sagittalImage,
                        index: $viewModel.sagittalIndex,
                        range: 0..<volume.width,
                        aspectRatio: volume.spacing.y / volume.spacing.z,
                        onIndexChanged: { viewModel.updateSagittalIndex($0) }
                    )
                    .frame(width: itemWidth, height: itemHeight)
                }
                
                HStack(spacing: 0) {
                    // Coronal Plane
                    MPRPlaneView(
                        title: "Coronal",
                        image: viewModel.coronalImage,
                        index: $viewModel.coronalIndex,
                        range: 0..<volume.height,
                        aspectRatio: volume.spacing.x / volume.spacing.z,
                        onIndexChanged: { viewModel.updateCoronalIndex($0) }
                    )
                    .frame(width: itemWidth, height: itemHeight)
                    
                    // Information Panel
                    VStack(alignment: .leading, spacing: 10) {
                        Text(volume.seriesDescription)
                            .font(.headline)
                        Text("Dimensions: \(volume.width)x\(volume.height)x\(volume.depth)")
                        Text("Spacing: \(String(format: "%.2f x %.2f x %.2f", volume.spacing.x, volume.spacing.y, volume.spacing.z)) mm")
                        
                        Divider().background(Color.gray)
                        
                        Text("Window Center: \(Int(viewModel.windowCenter))")
                        Text("Window Width: \(Int(viewModel.windowWidth))")
                        
                        Spacer()
                        
                        presetsMenu
                    }
                    .padding()
                    .foregroundColor(.white)
                    .frame(width: itemWidth, height: itemHeight)
                }
            }
        }
    }
    
    private var presetsMenu: some View {
        Menu {
            ForEach(MedicalPreset.allCases, id: \.self) { preset in
                Button(preset.displayName) {
                    viewModel.applyPreset(preset)
                }
            }
        } label: {
            Label("Windowing Presets", systemImage: "slider.horizontal.3")
                .padding(8)
                .background(Color.blue)
                .cornerRadius(8)
                .foregroundColor(.white)
        }
    }
    
    private func controlsView(volume: DicomSeriesVolume) -> some View {
        VStack(spacing: 4) {
            // Simplified global controls if needed, but per-plane sliders are in MPRPlaneView
            Text("Navigate planes using sliders or scroll")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.bottom, 8)
        }
        .padding(.horizontal)
    }
}

/// Individual plane viewer for MPR.
struct MPRPlaneView: View {
    let title: String
    let image: CGImage?
    @Binding var index: Int
    let range: Range<Int>
    let aspectRatio: Double // physical width / physical height
    let onIndexChanged: (Int) -> Void
    
    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topLeading) {
                Color.black
                
                if let cgImage = image {
                    // We need to handle the anatomical aspect ratio.
                    // DICOM pixels aren't always square.
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(aspectRatio, contentMode: .fit)
                } else {
                    Text("Rendering...")
                        .foregroundColor(.gray)
                }
                
                Text(title)
                    .font(.caption)
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
            }
            
            HStack {
                Text("\(index)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(width: 30)
                
                Slider(value: Binding(
                    get: { Double(index) },
                    set: { onIndexChanged(Int($0)) }
                ), in: Double(range.lowerBound)...Double(range.upperBound - 1))
                .accentColor(.blue)
            }
            .padding(.horizontal, 4)
        }
        .border(Color.gray.opacity(0.3), width: 0.5)
    }
}
