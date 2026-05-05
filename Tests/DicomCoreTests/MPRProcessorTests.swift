import XCTest
@testable import DicomCore
import simd

final class MPRProcessorTests: XCTestCase {
    
    var testVolume: DicomSeriesVolume!
    let width = 4
    let height = 3
    let depth = 2
    
    override func setUp() {
        super.setUp()
        
        // Create a synthetic volume where each voxel value is z*100 + y*10 + x
        let count = width * height * depth
        var voxels = [Int16](repeating: 0, count: count)
        
        for z in 0..<depth {
            for y in 0..<height {
                for x in 0..<width {
                    let value = Int16(z * 100 + y * 10 + x)
                    voxels[z * (width * height) + y * width + x] = value
                }
            }
        }
        
        let voxelData = voxels.withUnsafeBufferPointer { Data(buffer: $0) }
        
        testVolume = DicomSeriesVolume(
            voxels: voxelData,
            width: width,
            height: height,
            depth: depth,
            spacing: SIMD3<Double>(1.0, 1.0, 1.0),
            orientation: matrix_identity_double3x3,
            origin: .zero,
            rescaleSlope: 1.0,
            rescaleIntercept: 0.0,
            bitsAllocated: 16,
            isSignedPixel: false,
            seriesDescription: "Test Volume"
        )
    }
    
    func testExtractAxialSlice() {
        // Extract axial slice at z=1
        let slice = MPRProcessor.extractAxialSlice(from: testVolume, at: 1)
        
        XCTAssertEqual(slice.count, width * height)
        // Value at (x=2, y=1, z=1) should be 1*100 + 1*10 + 2 = 112
        XCTAssertEqual(slice[1 * width + 2], 112)
        // Value at (x=0, y=0, z=1) should be 100
        XCTAssertEqual(slice[0], 100)
    }
    
    func testExtractCoronalSlice() {
        // Coronal slice at y=1 (X-Z plane)
        let slice = MPRProcessor.extractCoronalSlice(from: testVolume, at: 1)
        
        XCTAssertEqual(slice.count, width * depth)
        // In MPRProcessor, coronal slice maps (z * sliceWidth + x)
        // Value at x=2, z=1 (which is volume x=2, y=1, z=1) should be 112
        XCTAssertEqual(slice[1 * width + 2], 112)
        // Value at x=0, z=0 (which is volume x=0, y=1, z=0) should be 10
        XCTAssertEqual(slice[0 * width + 0], 10)
    }
    
    func testExtractSagittalSlice() {
        // Sagittal slice at x=2 (Y-Z plane)
        let slice = MPRProcessor.extractSagittalSlice(from: testVolume, at: 2)
        
        XCTAssertEqual(slice.count, height * depth)
        // In MPRProcessor, sagittal slice maps (z * sliceWidth + y) where sliceWidth = volume.height
        // Value at y=1, z=1 (which is volume x=2, y=1, z=1) should be 112
        XCTAssertEqual(slice[1 * height + 1], 112)
        // Value at y=0, z=0 (which is volume x=2, y=0, z=0) should be 2
        XCTAssertEqual(slice[0 * height + 0], 2)
    }
    
    func testOutOfBoundsSafety() {
        let axial = MPRProcessor.extractAxialSlice(from: testVolume, at: 99)
        XCTAssertTrue(axial.isEmpty)
        
        let coronal = MPRProcessor.extractCoronalSlice(from: testVolume, at: 99)
        XCTAssertTrue(coronal.isEmpty)
        
        let sagittal = MPRProcessor.extractSagittalSlice(from: testVolume, at: 99)
        XCTAssertTrue(sagittal.isEmpty)
    }
}
