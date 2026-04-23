
import XCTest
@testable import DicomCore

final class DCMDecoderCineTests: XCTestCase {

    // MARK: - Tag Existence Tests

    func testCineTagsExist() {
        XCTAssertEqual(DicomTag.cineRate.rawValue, 0x00180040)
        XCTAssertEqual(DicomTag.frameTime.rawValue, 0x00181063)
        XCTAssertEqual(DicomTag.frameTimeVector.rawValue, 0x00181065)
    }

    // MARK: - RLEDecoder Tests

    func testRLEDecoderBasic() {
        // Create a simple RLE-encoded frame (8-bit grayscale, 4x4)
        // Header: 1 segment, offset 64
        var data = Data(repeating: 0, count: 64 + 1 + 16)
        
        // Number of segments = 1
        data[0] = 0x01; data[1] = 0x00; data[2] = 0x00; data[3] = 0x00
        // Offset of segment 1 = 64
        data[4] = 0x40; data[5] = 0x00; data[6] = 0x00; data[7] = 0x00
        
        // Segment data: Literal run of 16 bytes (n=15)
        data[64] = 15
        for i in 0..<16 {
            data[65+i] = UInt8(i)
        }
        
        let decoded = RLEDecoder.decode(data: data, width: 4, height: 4, bitsAllocated: 8, samplesPerPixel: 1)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 16)
        if let decoded = decoded {
            for i in 0..<16 {
                XCTAssertEqual(decoded[i], UInt8(i))
            }
        }
    }

    func testRLEDecoderReplicateRun() {
        // Header: 1 segment, offset 64
        var data = Data(repeating: 0, count: 64 + 2)
        data[0] = 0x01; data[1] = 0x00; data[2] = 0x00; data[3] = 0x00
        data[4] = 0x40; data[5] = 0x00; data[6] = 0x00; data[7] = 0x00
        
        // Segment data: Replicate run of 16 bytes of value 0xAA (n = 257 - 16 = 241)
        data[64] = 241
        data[65] = 0xAA
        
        let decoded = RLEDecoder.decode(data: data, width: 4, height: 4, bitsAllocated: 8, samplesPerPixel: 1)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 16)
        if let decoded = decoded {
            for i in 0..<16 {
                XCTAssertEqual(decoded[i], 0xAA)
            }
        }
    }

    // MARK: - Encapsulated Offset Parser Tests

    func testParseEncapsulatedFrameOffsets() {
        // Mock DICOM encapsulated pixel data
        // BOT with 2 entries pointing to 2 frames
        var data = Data()
        
        // (FFFE,E000) Item Tag
        data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
        // Length 8
        data.append(contentsOf: [0x08, 0x00, 0x00, 0x00])
        // BOT Entry 1: Offset 0
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        // BOT Entry 2: Offset 20 (relative to first item tag)
        data.append(contentsOf: [0x14, 0x00, 0x00, 0x00])
        
        // Frame 1: Item Tag (FFFE,E000)
        data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
        // Length 10
        data.append(contentsOf: [0x0A, 0x00, 0x00, 0x00])
        // Data (10 bytes)
        data.append(Data(repeating: 0x11, count: 10))
        
        // Padding (2 bytes)
        data.append(contentsOf: [0x00, 0x00])
        
        // Frame 2: Item Tag (FFFE,E000)
        data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
        // Length 10
        data.append(contentsOf: [0x0A, 0x00, 0x00, 0x00])
        // Data (10 bytes)
        data.append(Data(repeating: 0x22, count: 10))
        
        // (FFFE,E0DD) Sequence Delimitation Tag
        data.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0])
        // Length 0
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        
        let offsets = DCMPixelReader.parseEncapsulatedFrameOffsets(data: data, offset: 0)
        XCTAssertNotNil(offsets)
        XCTAssertEqual(offsets?.count, 2)
        XCTAssertEqual(offsets?[0].length, 10)
        XCTAssertEqual(offsets?[1].length, 10)
        
        let frame1 = DCMPixelReader.extractEncapsulatedFrame(data: data, frameIndex: 0, frameOffsets: offsets!)
        XCTAssertEqual(frame1?.first, 0x11)
        
        let frame2 = DCMPixelReader.extractEncapsulatedFrame(data: data, frameIndex: 1, frameOffsets: offsets!)
        XCTAssertEqual(frame2?.first, 0x22)
    }

    // MARK: - DCMDecoder Property Tests

    func testDerivedFrameRate() {
        let decoder = MockDicomDecoder()
        
        // Default
        XCTAssertEqual(decoder.derivedFrameRate, 30.0)
        
        // cineRate takes priority
        decoder.cineRate = 60.0
        decoder.frameTime = 100.0 // 10 fps
        XCTAssertEqual(decoder.derivedFrameRate, 60.0)
        
        // fallback to frameTime
        decoder.cineRate = 0.0
        XCTAssertEqual(decoder.derivedFrameRate, 10.0)
    }
}
