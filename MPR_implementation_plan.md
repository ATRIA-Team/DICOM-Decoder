# Goal: Enable 12-Bit Depth Support in DICOM-Decoder

The `DS_CorCTA` scan failed to load on the physical device because its `BitsStored` is 12 (reported as `bitDepth` of 12). The remote `DICOM-Decoder` library currently strictly requires `bitDepth == 16`. Since 12-bit CT data is physically stored within 16-bit integers (2 bytes per pixel), the exact same 16-bit decoding pipeline can process it natively.

Because Xcode is pulling the `DICOM-Decoder` package from GitHub (`https://github.com/ATRIA-Team/DICOM-Decoder.git`), the changes I made locally were ignored by the build system. 

To fix this, you need to apply the following 3 small changes directly to your local `DICOM-Decoder` codebase at `/Users/michelecoppola/Desktop/swiftUI projects/DICOM-Decoder` on the `multi-plane-ct` branch, and then push them to GitHub.

## User Action Required

Please apply the following changes to your `DICOM-Decoder` repository.

### 1. Update `DicomSeriesLoader.swift`

**File:** `Sources/DicomCore/DicomSeriesLoader.swift`

Modify the validation checks to accept 12-bit depths:

```diff
             guard decoder.samplesPerPixel == 1 else {
                 throw DicomSeriesLoaderError.unsupportedSamplesPerPixel(decoder.samplesPerPixel)
             }
-            guard decoder.bitDepth == 16 else {
+            guard decoder.bitDepth == 16 || decoder.bitDepth == 12 else {
                 throw DicomSeriesLoaderError.unsupportedBitDepth(decoder.bitDepth)
             }
```

```diff
         guard decoder.dicomFileReadSuccess,
               decoder.width == expectedWidth,
               decoder.height == expectedHeight,
-              decoder.bitDepth == 16,
+              (decoder.bitDepth == 16 || decoder.bitDepth == 12),
               decoder.samplesPerPixel == 1 else {
             throw DicomSeriesLoaderError.failedToDecode(url)
         }
```

### 2. Update `DCMDecoder.swift`

**File:** `Sources/DicomCore/DCMDecoder.swift`

Modify the 16-bit extraction methods to also handle 12-bit data:

```diff
     public func getDownsampledPixels16(maxDimension: Int = 150) -> (pixels: [UInt16], width: Int, height: Int)? {
         return synchronized {
-            guard samplesPerPixel == 1 && bitDepth == 16 else { return nil }
+            guard samplesPerPixel == 1 && (bitDepth == 16 || bitDepth == 12) else { return nil }
             guard offset > 0 else { return nil }
```

```diff
-            // Validate this is a 16-bit grayscale image
-            guard bitDepth == 16, samplesPerPixel == 1 else {
-                logger.warning("getPixels16(range:) called on non-16-bit grayscale image (bitDepth=\(bitDepth), samplesPerPixel=\(samplesPerPixel))")
+            // Validate this is a 16-bit (or 12-bit) grayscale image
+            guard (bitDepth == 16 || bitDepth == 12), samplesPerPixel == 1 else {
+                logger.warning("getPixels16(range:) called on non-16/12-bit grayscale image (bitDepth=\(bitDepth), samplesPerPixel=\(samplesPerPixel))")
                 return nil
             }
```

### 3. Update `DCMPixelReader.swift`

**File:** `Sources/DicomCore/DCMPixelReader.swift`

Allow the 16-bit pixel reading loop to execute for 12-bit images (which use 2 bytes per pixel):

```diff
-        // Grayscale 16‑bit
-        if samplesPerPixel == 1 && bitDepth == 16 {
+        // Grayscale 16‑bit or 12-bit (stored in 16 bits)
+        if samplesPerPixel == 1 && (bitDepth == 16 || bitDepth == 12) {
             guard let metrics = computePixelMetrics(
                 width: width,
                 height: height,
```

---

## Verification Plan

Once you have applied these changes:
1. **Commit and push** them to the `multi-plane-ct` branch of your `DICOM-Decoder` repository.
2. In your `DemoMultiPlanarCT` Xcode project, go to **File > Packages > Update to Latest Package Versions**.
3. Rebuild and run the app on your Vision Pro.
4. Select the `DS_CorCTA` series; it should now bypass the `unsupportedBitDepth` error and successfully load the 571 slices into the MPR viewer.
