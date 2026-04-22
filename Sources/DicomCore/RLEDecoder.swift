//
//  RLEDecoder.swift
//
//  Native decoder for DICOM RLE Lossless Transfer Syntax
//  (UID 1.2.840.10008.1.2.5).  This codec is the dominant
//  lossless compression format on ultrasound machines from
//  GE, Siemens and Philips and is therefore the most important
//  single codec to implement for Cine-Echocardiography support.
//
//  ## RLE Lossless Format (DICOM PS 3.5, Annex G)
//
//  Each encapsulated RLE frame begins with a 64-byte header:
//    Bytes  0-3:  numberOfSegments (UInt32 LE)
//    Bytes  4-63: up to 15 segment offsets (UInt32 LE each),
//                 measured from the start of this header.
//
//  Each segment is a PackBits-style byte stream:
//    n in  0..127  → copy the next (n+1) raw bytes verbatim
//    n in 129..255 → repeat the next byte (257 - n) times
//    n == 128      → NOP (ignored)
//
//  Segment layout per pixel format:
//    8-bit  grayscale, 1 sample → 1 segment (high byte)
//    16-bit grayscale, 1 sample → 2 segments (high byte, low byte)
//    24-bit RGB,      3 samples → 3 segments (R high, G high, B high)
//                                (or 6 segments for 16-bit RGB, rare)
//
//  The decoder re-interleaves the byte planes according to the
//  DICOM byte ordering convention (most-significant byte first
//  within each 16-bit word).
//

import Foundation

/// Native decoder for DICOM RLE Lossless (Transfer Syntax `1.2.840.10008.1.2.5`).
///
/// Designed to be used by `DCMPixelReader.decodeCompressedPixelData()` after
/// encapsulated frame extraction.  All methods are static and allocation-free
/// on the hot path (segment decoding works directly on `Data` slices).
internal struct RLEDecoder {

    // MARK: - Public Entry Point

    /// Decodes a single RLE-compressed frame extracted from the
    /// encapsulated pixel data sequence.
    ///
    /// - Parameters:
    ///   - data:           The RLE frame bytes starting at the 64-byte header.
    ///   - width:          Expected image width in pixels.
    ///   - height:         Expected image height in pixels.
    ///   - bitsAllocated:  Bits per sample (8 or 16).
    ///   - samplesPerPixel: 1 (grayscale) or 3 (RGB).
    ///   - logger:         Optional diagnostic logger.
    /// - Returns: Decompressed row-major pixel bytes, or `nil` on failure.
    ///
    /// Output layout mirrors the uncompressed `readPixels()` convention:
    ///   - 8-bit gray → `[UInt8]` length `width × height`
    ///   - 16-bit gray → `[UInt8]` length `width × height × 2` (LE pairs)
    ///   - 24-bit RGB  → `[UInt8]` length `width × height × 3` (interleaved RGB)
    internal static func decode(
        data: Data,
        width: Int,
        height: Int,
        bitsAllocated: Int,
        samplesPerPixel: Int,
        logger: AnyLogger? = nil
    ) -> Data? {

        guard width > 0, height > 0 else {
            logger?.warning("[RLE] Invalid dimensions: \(width)×\(height)")
            return nil
        }
        guard data.count >= 64 else {
            logger?.warning("[RLE] Frame too short for RLE header: \(data.count) bytes")
            return nil
        }

        // --- Parse the 64-byte header ------------------------------------------
        guard let numberOfSegments = readUInt32LE(data, at: 0) else {
            logger?.warning("[RLE] Could not read segment count")
            return nil
        }

        let expectedSegments: Int
        switch (samplesPerPixel, bitsAllocated) {
        case (1,  8): expectedSegments = 1
        case (1, 16): expectedSegments = 2
        case (3,  8): expectedSegments = 3
        case (3, 16): expectedSegments = 6
        default:
            logger?.warning("[RLE] Unsupported format: samplesPerPixel=\(samplesPerPixel) bitsAllocated=\(bitsAllocated)")
            return nil
        }

        guard numberOfSegments >= UInt32(expectedSegments) else {
            logger?.warning("[RLE] Header declares \(numberOfSegments) segments, expected \(expectedSegments)")
            return nil
        }

        // Read segment offsets (up to 15 slots in the header, indices 1-15)
        var segmentOffsets = [Int]()
        for i in 0..<expectedSegments {
            let headerSlot = i + 1            // slots 1..15
            guard let rawOffset = readUInt32LE(data, at: headerSlot * 4) else {
                logger?.warning("[RLE] Could not read offset for segment \(i)")
                return nil
            }
            segmentOffsets.append(Int(rawOffset))
        }

        // --- Decode each segment -----------------------------------------------
        let pixelsPerFrame = width * height
        var planes = [[UInt8]]()

        for (idx, segOffset) in segmentOffsets.enumerated() {
            guard segOffset < data.count else {
                logger?.warning("[RLE] Segment \(idx) offset \(segOffset) out of bounds")
                return nil
            }

            // The segment extends to the start of the next segment or end of data
            let nextOffset: Int
            if idx + 1 < segmentOffsets.count {
                nextOffset = segmentOffsets[idx + 1]
            } else {
                nextOffset = data.count
            }

            guard nextOffset <= data.count, nextOffset > segOffset else {
                logger?.warning("[RLE] Segment \(idx) has invalid range [\(segOffset), \(nextOffset))")
                return nil
            }

            let segment = data[data.startIndex + segOffset ..< data.startIndex + nextOffset]
            guard let plane = decodeSegment(segment, expectedBytes: pixelsPerFrame, logger: logger) else {
                logger?.warning("[RLE] Segment \(idx) decode failed")
                return nil
            }
            planes.append(plane)
        }

        // --- Re-interleave byte planes into the output layout ------------------
        return interleave(planes: planes,
                          pixelsPerFrame: pixelsPerFrame,
                          samplesPerPixel: samplesPerPixel,
                          bitsAllocated: bitsAllocated,
                          logger: logger)
    }

    // MARK: - Segment Decoder (PackBits)

    /// Decodes a single PackBits-style RLE segment into `expectedBytes` raw bytes.
    private static func decodeSegment(
        _ segment: Data,
        expectedBytes: Int,
        logger: AnyLogger? = nil
    ) -> [UInt8]? {
        var output = [UInt8]()
        output.reserveCapacity(expectedBytes)

        var i = segment.startIndex
        let end = segment.endIndex

        while i < end {
            let n = Int(segment[i])
            i = segment.index(after: i)

            if n == 128 {
                // NOP — skip
                continue
            } else if n < 128 {
                // Literal run: copy next (n+1) bytes
                let count = n + 1
                guard segment.distance(from: i, to: end) >= count else {
                    logger?.warning("[RLE] Literal run overflows segment boundary")
                    return nil
                }
                output.append(contentsOf: segment[i ..< segment.index(i, offsetBy: count)])
                i = segment.index(i, offsetBy: count)
            } else {
                // Replicate run: repeat next byte (257 - n) times
                let count = 257 - n
                guard i < end else {
                    logger?.warning("[RLE] Replicate run: missing value byte")
                    return nil
                }
                let byte = segment[i]
                i = segment.index(after: i)
                output.append(contentsOf: repeatElement(byte, count: count))
            }

            if output.count >= expectedBytes { break }
        }

        guard output.count >= expectedBytes else {
            logger?.warning("[RLE] Segment decoded \(output.count) bytes; expected \(expectedBytes)")
            return nil
        }

        // Clamp to expected size (DICOM allows padding)
        if output.count > expectedBytes {
            output = Array(output.prefix(expectedBytes))
        }
        return output
    }

    // MARK: - Plane Interleaving

    /// Reassembles decoded byte planes into the interleaved pixel layout
    /// used by `DCMPixelReader`.
    ///
    /// DICOM RLE stores bytes in most-significant-first, planar order.
    /// For 16-bit images: planes[0] = high bytes, planes[1] = low bytes.
    /// For 24-bit RGB:    planes[0]=R, planes[1]=G, planes[2]=B (8-bit each).
    private static func interleave(
        planes: [[UInt8]],
        pixelsPerFrame: Int,
        samplesPerPixel: Int,
        bitsAllocated: Int,
        logger: AnyLogger? = nil
    ) -> Data? {
        switch (samplesPerPixel, bitsAllocated) {

        case (1, 8):
            // Single plane, no interleaving needed
            return Data(planes[0])

        case (1, 16):
            // Two planes: high byte (planes[0]), low byte (planes[1])
            // Output: little-endian UInt16 pairs (low byte first), matching readPixels() convention
            guard planes.count >= 2 else { return nil }
            var output = [UInt8](repeating: 0, count: pixelsPerFrame * 2)
            let hi = planes[0]
            let lo = planes[1]
            for i in 0..<pixelsPerFrame {
                output[i * 2]     = lo[i]   // low byte first (little-endian)
                output[i * 2 + 1] = hi[i]   // high byte second
            }
            return Data(output)

        case (3, 8):
            // Three planes: R (planes[0]), G (planes[1]), B (planes[2])
            // Interleave as RGB triples
            guard planes.count >= 3 else { return nil }
            var output = [UInt8](repeating: 0, count: pixelsPerFrame * 3)
            let r = planes[0]; let g = planes[1]; let b = planes[2]
            for i in 0..<pixelsPerFrame {
                output[i * 3]     = r[i]
                output[i * 3 + 1] = g[i]
                output[i * 3 + 2] = b[i]
            }
            return Data(output)

        case (3, 16):
            // Six planes: Rhi, Ghi, Bhi, Rlo, Glo, Blo
            // Output: interleaved RGB UInt16 LE triples (rare, but correct)
            guard planes.count >= 6 else { return nil }
            var output = [UInt8](repeating: 0, count: pixelsPerFrame * 6)
            for i in 0..<pixelsPerFrame {
                let base = i * 6
                output[base]     = planes[3][i]  // R low
                output[base + 1] = planes[0][i]  // R high
                output[base + 2] = planes[4][i]  // G low
                output[base + 3] = planes[1][i]  // G high
                output[base + 4] = planes[5][i]  // B low
                output[base + 5] = planes[2][i]  // B high
            }
            return Data(output)

        default:
            logger?.warning("[RLE] Unsupported plane configuration: samplesPerPixel=\(samplesPerPixel) bitsAllocated=\(bitsAllocated)")
            return nil
        }
    }

    // MARK: - Byte Helpers

    private static func readUInt32LE(_ data: Data, at byteOffset: Int) -> UInt32? {
        guard byteOffset >= 0, byteOffset + 4 <= data.count else { return nil }
        return data.withUnsafeBytes { rawBuffer in
            let base = rawBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self).advanced(by: byteOffset)
            return UInt32(base[0])
                | (UInt32(base[1]) << 8)
                | (UInt32(base[2]) << 16)
                | (UInt32(base[3]) << 24)
        }
    }
}
