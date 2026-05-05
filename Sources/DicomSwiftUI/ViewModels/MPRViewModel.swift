//
//  MPRViewModel.swift
//  DicomSwiftUI
//
//  Created by Gemini CLI.
//

import Foundation
import SwiftUI
import Combine
import DicomCore

/// View model for managing Multi-Planar Reconstruction (MPR) display state.
@MainActor
public final class MPRViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var volume: DicomSeriesVolume?
    @Published public var isLoading = false
    @Published public var error: Error?
    
    // Slice Indices
    @Published public var axialIndex: Int = 0
    @Published public var coronalIndex: Int = 0
    @Published public var sagittalIndex: Int = 0
    
    // Rendered Images
    @Published public var axialImage: CGImage?
    @Published public var coronalImage: CGImage?
    @Published public var sagittalImage: CGImage?
    
    // Windowing State
    @Published public var windowCenter: Double = 40.0
    @Published public var windowWidth: Double = 400.0
    
    // MARK: - Properties
    
    private let loader = DicomSeriesLoader()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    public init(volume: DicomSeriesVolume? = nil) {
        self.volume = volume
        if let volume = volume {
            setupInitialIndices(for: volume)
            renderAllPlanes()
        }
    }
    
    // MARK: - Public Methods
    
    /// Loads a DICOM volume from a directory.
    public func loadVolume(from directory: URL) async {
        isLoading = true
        error = nil
        
        do {
            let loadedVolume = try await Task.detached(priority: .userInitiated) {
                try self.loader.loadSeries(in: directory)
            }.value
            
            self.volume = loadedVolume
            setupInitialIndices(for: loadedVolume)
            
            // Use optimal windowing from the middle axial slice
            let midSlice = MPRProcessor.extractAxialSlice(from: loadedVolume, at: loadedVolume.depth / 2)
            let optimal = DCMWindowingProcessor.calculateOptimalWindowLevel(pixels16: midSlice)
            self.windowCenter = optimal.center
            self.windowWidth = optimal.width
            
            renderAllPlanes()
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    /// Updates the axial slice index and re-renders the plane.
    public func updateAxialIndex(_ index: Int) {
        guard let volume = volume, index >= 0 && index < volume.depth else { return }
        axialIndex = index
        renderAxial()
    }
    
    /// Updates the coronal slice index and re-renders the plane.
    public func updateCoronalIndex(_ index: Int) {
        guard let volume = volume, index >= 0 && index < volume.height else { return }
        coronalIndex = index
        renderCoronal()
    }
    
    /// Updates the sagittal slice index and re-renders the plane.
    public func updateSagittalIndex(_ index: Int) {
        guard let volume = volume, index >= 0 && index < volume.width else { return }
        sagittalIndex = index
        renderSagittal()
    }
    
    /// Updates windowing and re-renders all planes.
    public func updateWindowing(center: Double, width: Double) {
        windowCenter = center
        windowWidth = width
        renderAllPlanes()
    }
    
    public func applyPreset(_ preset: MedicalPreset) {
        let values = DCMWindowingProcessor.getPresetValues(preset: preset)
        updateWindowing(center: values.center, width: values.width)
    }
    
    // MARK: - Rendering
    
    public func renderAllPlanes() {
        renderAxial()
        renderCoronal()
        renderSagittal()
    }
    
    private func renderAxial() {
        guard let volume = volume else { return }
        let pixels16 = MPRProcessor.extractAxialSlice(from: volume, at: axialIndex)
        axialImage = renderPixels(pixels16, width: volume.width, height: volume.height)
    }
    
    private func renderCoronal() {
        guard let volume = volume else { return }
        let pixels16 = MPRProcessor.extractCoronalSlice(from: volume, at: coronalIndex)
        // Coronal: Width = Volume Width, Height = Volume Depth
        coronalImage = renderPixels(pixels16, width: volume.width, height: volume.depth)
    }
    
    private func renderSagittal() {
        guard let volume = volume else { return }
        let pixels16 = MPRProcessor.extractSagittalSlice(from: volume, at: sagittalIndex)
        // Sagittal: Width = Volume Height, Height = Volume Depth
        sagittalImage = renderPixels(pixels16, width: volume.height, height: volume.depth)
    }
    
    private func renderPixels(_ pixels16: [UInt16], width: Int, height: Int) -> CGImage? {
        // Use applyWindowLevel with the signature present in DCMWindowingProcessor.swift
        guard let pixels8Data = DCMWindowingProcessor.applyWindowLevel(
            pixels16: pixels16,
            center: windowCenter,
            width: windowWidth
        ) else { return nil }
        
        return CGImageFactory.createImage(from: Array(pixels8Data), width: width, height: height)
    }
    
    private func setupInitialIndices(for volume: DicomSeriesVolume) {
        axialIndex = volume.depth / 2
        coronalIndex = volume.height / 2
        sagittalIndex = volume.width / 2
    }
}
