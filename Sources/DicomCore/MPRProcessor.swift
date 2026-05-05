//
//  MPRProcessor.swift
//  DicomCore
//
//  Created by Gemini CLI.
//

import Foundation
import simd

/// Utility for extracting orthogonal slices from a 3D DICOM volume.
public struct MPRProcessor {
    
    /// Extracts an axial slice (X-Y plane) from the volume at a given Z index.
    /// - Parameters:
    ///   - volume: The 3D DICOM volume.
    ///   - z: The index along the Z-axis (depth).
    /// - Returns: An array of 16-bit pixels for the slice.
    public static func extractAxialSlice(from volume: DicomSeriesVolume, at z: Int) -> [UInt16] {
        guard z >= 0 && z < volume.depth else { return [] }
        
        let sliceSize = volume.width * volume.height
        let startOffset = z * sliceSize
        
        return volume.voxels.withUnsafeBytes { rawBuffer in
            let voxels = rawBuffer.bindMemory(to: Int16.self)
            var slice = [UInt16](repeating: 0, count: sliceSize)
            
            for i in 0..<sliceSize {
                let value = voxels[startOffset + i]
                slice[i] = toUInt16(value, isSigned: volume.isSignedPixel)
            }
            return slice
        }
    }
    
    /// Extracts a coronal slice (X-Z plane) from the volume at a given Y index.
    /// - Parameters:
    ///   - volume: The 3D DICOM volume.
    ///   - y: The index along the Y-axis (height).
    /// - Returns: An array of 16-bit pixels for the slice.
    public static func extractCoronalSlice(from volume: DicomSeriesVolume, at y: Int) -> [UInt16] {
        guard y >= 0 && y < volume.height else { return [] }
        
        let sliceWidth = volume.width
        let sliceHeight = volume.depth
        var slice = [UInt16](repeating: 0, count: sliceWidth * sliceHeight)
        
        volume.voxels.withUnsafeBytes { rawBuffer in
            let voxels = rawBuffer.bindMemory(to: Int16.self)
            
            for z in 0..<volume.depth {
                let volumeZOffset = z * volume.width * volume.height
                let volumeYOffset = y * volume.width
                
                for x in 0..<volume.width {
                    let value = voxels[volumeZOffset + volumeYOffset + x]
                    // Coronal slice is traditionally viewed with Z increasing upwards or downwards.
                    // Here we map Z to the 'height' of the 2D output slice.
                    slice[z * sliceWidth + x] = toUInt16(value, isSigned: volume.isSignedPixel)
                }
            }
        }
        return slice
    }
    
    /// Extracts a sagittal slice (Y-Z plane) from the volume at a given X index.
    /// - Parameters:
    ///   - volume: The 3D DICOM volume.
    ///   - x: The index along the X-axis (width).
    /// - Returns: An array of 16-bit pixels for the slice.
    public static func extractSagittalSlice(from volume: DicomSeriesVolume, at x: Int) -> [UInt16] {
        guard x >= 0 && x < volume.width else { return [] }
        
        let sliceWidth = volume.height
        let sliceHeight = volume.depth
        var slice = [UInt16](repeating: 0, count: sliceWidth * sliceHeight)
        
        volume.voxels.withUnsafeBytes { rawBuffer in
            let voxels = rawBuffer.bindMemory(to: Int16.self)
            
            for z in 0..<volume.depth {
                let volumeZOffset = z * volume.width * volume.height
                
                for y in 0..<volume.height {
                    let value = voxels[volumeZOffset + y * volume.width + x]
                    slice[z * sliceWidth + y] = toUInt16(value, isSigned: volume.isSignedPixel)
                }
            }
        }
        return slice
    }
    
    // MARK: - Private Helpers
    
    /// Converts an Int16 voxel value to UInt16, handling the signed-to-unsigned shift used during loading.
    private static func toUInt16(_ value: Int16, isSigned: Bool) -> UInt16 {
        if isSigned {
            // DicomSeriesLoader shifts signed pixels by adding Int16.min and storing as Int16.
            // To get back to the original range (e.g. -1024 to 3071) as bit-pattern, 
            // we need to reverse that or handle the offset.
            // Actually, DCMWindowingProcessor expects UInt16 where 0 is the lowest possible value.
            // If we want to support Hounsfield Units, we should map them so they fit in UInt16.
            // Standard shift: HU + 1024 (or similar).
            // But here we just want to undo the Loader's shift to get back to original UInt16 bit pattern
            // if it was originally UInt16, or keep the shifted value if it's easier for windowing.
            
            // Re-reversing the DicomSeriesLoader.decodeSlice logic:
            // signed = value (as Int32) + Int16.min
            // So value = signed - Int16.min
            let originalValue = Int32(value) - Int32(Int16.min)
            return UInt16(clamping: originalValue)
        } else {
            return UInt16(bitPattern: value)
        }
    }
}

private extension UInt16 {
    init(clamping value: Int32) {
        if value < 0 {
            self = 0
        } else if value > Int32(UInt16.max) {
            self = UInt16.max
        } else {
            self = UInt16(value)
        }
    }
}
