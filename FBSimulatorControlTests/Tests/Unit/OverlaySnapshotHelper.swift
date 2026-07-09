/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Disabled during swift-format 6.3 rollout, feel free to remove:
// swift-format-ignore-file: OrderedImports

import AppKit
import CoreGraphics
import CoreVideo
import XCTest

@testable import FBSimulatorControl

/// Lightweight snapshot testing for FBOverlayRenderer output.
///
/// Converts CVPixelBuffer to PNG and compares against reference images stored
/// in `Fixtures/snapshots/` and bundled via `fb_apple_resource` in BUCK.
///
/// To record new snapshots, temporarily set `recordSnapshots = true`, run tests,
/// and copy the emitted PNGs into `Fixtures/snapshots/`.
enum OverlaySnapshotHelper {

  /// Set to `true` temporarily to record new snapshots.
  /// Tests will fail with PNGs written to `$TMPDIR` — copy them into `Fixtures/snapshots/`.
  static let recordSnapshots = false

  /// Convert a CVPixelBuffer (BGRA) to PNG data.
  static func pngData(from buffer: CVPixelBuffer) -> Data {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
      fatalError("CVPixelBuffer has no base address")
    }

    let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    guard
      let context = CGContext(
        data: baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo
      )
    else {
      fatalError("Failed to create CGContext from CVPixelBuffer")
    }

    guard let cgImage = context.makeImage() else {
      fatalError("Failed to create CGImage from CGContext")
    }

    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else {
      fatalError("Failed to encode CGImage as PNG")
    }
    return data
  }

  /// Maximum per-channel difference allowed between pixels (0–255).
  /// Tolerates minor antialiasing differences across macOS versions while
  /// still catching positioning, sizing, and color changes.
  static let perChannelTolerance: UInt8 = 4

  /// Assert that the buffer matches a reference snapshot PNG from the test bundle.
  ///
  /// Reference PNGs are stored in `Fixtures/snapshots/` and bundled via `fb_apple_resource`.
  /// - In record mode: writes PNG to `$TMPDIR` for copying into `Fixtures/snapshots/`.
  /// - In normal mode: loads reference from bundle, compares pixel data with tolerance.
  /// - On mismatch: writes actual PNG to `$TMPDIR` for visual inspection.
  static func assertSnapshot(
    _ buffer: CVPixelBuffer,
    named name: String,
    tolerance: UInt8? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let actualData = pngData(from: buffer)

    if recordSnapshots {
      let tmpPath = writeTmp(actualData, named: name)
      let b64 = actualData.base64EncodedString()
      XCTFail(
        "RECORD[\(name)]:\(b64):END_RECORD\n  Written to \(tmpPath)",
        file: file, line: line
      )
      return
    }

    let bundle = Bundle(for: _BundleAnchor.self)
    guard let referenceURL = bundle.url(forResource: name, withExtension: "png") else {
      let tmpPath = writeTmp(actualData, named: name)
      XCTFail(
        "No reference '\(name).png' in test bundle. Set recordSnapshots=true to generate. Actual written to \(tmpPath)",
        file: file, line: line
      )
      return
    }

    guard let referenceData = try? Data(contentsOf: referenceURL) else {
      XCTFail("Failed to load reference '\(name).png' from \(referenceURL)", file: file, line: line)
      return
    }

    let effectiveTolerance = tolerance ?? perChannelTolerance
    let mismatch = comparePixels(actual: actualData, reference: referenceData, tolerance: effectiveTolerance)
    if let mismatch {
      let tmpPath = writeTmp(actualData, named: name)
      XCTFail(
        "Snapshot mismatch for '\(name)': \(mismatch)\n  Actual written to \(tmpPath)",
        file: file, line: line
      )
    }
  }

  /// Compare two PNG images at the pixel level with per-channel tolerance.
  /// Returns a description of the mismatch, or nil if images match within tolerance.
  private static func comparePixels(actual: Data, reference: Data, tolerance: UInt8) -> String? {
    guard let actualImage = NSBitmapImageRep(data: actual),
      let referenceImage = NSBitmapImageRep(data: reference)
    else {
      return "Failed to decode PNG data"
    }

    let w = actualImage.pixelsWide
    let h = actualImage.pixelsHigh
    if w != referenceImage.pixelsWide || h != referenceImage.pixelsHigh {
      return "Size mismatch: actual \(w)x\(h) vs reference \(referenceImage.pixelsWide)x\(referenceImage.pixelsHigh)"
    }

    guard let actualPixels = actualImage.bitmapData,
      let refPixels = referenceImage.bitmapData
    else {
      return "Failed to access bitmap data"
    }

    let bpp = actualImage.bitsPerPixel / 8
    var maxDiff: UInt8 = 0
    var diffCount = 0
    for y in 0..<h {
      for x in 0..<w {
        let offset = (y * actualImage.bytesPerRow) + (x * bpp)
        for c in 0..<min(bpp, 4) {
          let a = actualPixels[offset + c]
          let r = refPixels[offset + c]
          let diff = a > r ? a - r : r - a
          if diff > tolerance {
            diffCount += 1
            maxDiff = max(maxDiff, diff)
          }
        }
      }
    }

    if diffCount > 0 {
      return "\(diffCount) channel values differ by more than \(tolerance) (max diff: \(maxDiff))"
    }
    return nil
  }

  // MARK: - Private

  /// Anchor class for locating the test bundle via `Bundle(for:)`.
  private class _BundleAnchor {}

  private static func writeTmp(_ data: Data, named name: String) -> String {
    let tmpDir = NSTemporaryDirectory()
    let path = (tmpDir as NSString).appendingPathComponent("\(name)_actual.png")
    try? data.write(to: URL(fileURLWithPath: path))
    return path
  }
}

// MARK: - Test Case Data Model

/// Declarative description of an overlay rendering to snapshot-test.
struct OverlaySnapshotCase {
  let name: String
  let width: Int
  let height: Int
  var scaleFactor: CGFloat = 1.0
  var transform: FBOverlayCoordinateTransform?
  var overlays: [FBOverlayShape] = []
  var bottomBarContent: FBBarContent?
  /// Per-channel tolerance override for this case. Nil uses the default (4).
  /// Text-rendering snapshots need higher tolerance (~40) due to font rendering
  /// differences across macOS versions.
  var tolerance: UInt8?
}

/// Render the described case and assert the snapshot matches the reference.
func assertOverlaySnapshot(
  _ testCase: OverlaySnapshotCase,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  let renderer: FBOverlayRenderer
  if let transform = testCase.transform {
    renderer = FBOverlayRenderer(transform: transform)
  } else {
    renderer = FBOverlayRenderer(
      width: testCase.width, height: testCase.height,
      scaleFactor: testCase.scaleFactor
    )
  }
  if !testCase.overlays.isEmpty {
    renderer.render(overlays: testCase.overlays)
  }
  if let content = testCase.bottomBarContent {
    renderer.setBarContent(content, position: "bottom")
  }
  OverlaySnapshotHelper.assertSnapshot(
    renderer.buffer, named: testCase.name,
    tolerance: testCase.tolerance,
    file: file, line: line
  )
}
