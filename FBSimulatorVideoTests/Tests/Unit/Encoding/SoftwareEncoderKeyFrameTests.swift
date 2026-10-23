/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import CoreVideo
@testable import FBVideoCore
import Foundation
import Testing
import VideoToolbox
import os

/// What the encoders VideoToolbox falls back to produce, as the file writers see it: a recording whose hardware
/// encoder was refused is made by a software one, and has to come out as a playable file.
@Suite
final class SoftwareEncoderKeyFrameTests {

  private let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).webm")

  deinit {
    try? FileManager.default.removeItem(at: fileURL)
  }

  private struct Encoded {
    var samples: [CMSampleBuffer] = []
    var failures: [String] = []
  }

  /// Encodes `frameCount` identical frames with a real software (hardware-disabled) encoder, forcing the first to be a
  /// keyframe and setting no other keyframe within the sequence. Fails unless every frame comes back as a sample.
  private func softwareSamples(codec: CMVideoCodecType, frameCount: Int = 6) throws -> [CMSampleBuffer] {
    let width = 128
    let height = 128
    let attributes: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
    ]
    var created: VTCompressionSession?
    let status = VTCompressionSessionCreate(
      allocator: nil, width: Int32(width), height: Int32(height), codecType: codec,
      encoderSpecification: [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: false] as CFDictionary,
      imageBufferAttributes: attributes as CFDictionary, compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
      compressionSessionOut: &created)
    let session = try #require(created, "a software encoder for the codec: \(status)")
    defer { VTCompressionSessionInvalidate(session) }
    VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
    VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
    VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: 1000))
    let encoded = OSAllocatedUnfairLock<Encoded>(uncheckedState: Encoded())
    for index in 0..<frameCount {
      var pixelBuffer: CVPixelBuffer?
      CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes as CFDictionary, &pixelBuffer)
      let buffer = try #require(pixelBuffer)
      CVPixelBufferLockBaseAddress(buffer, [])
      for plane in 0..<2 {
        if let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) {
          memset(base, Int32(plane * 50 + 60), CVPixelBufferGetBytesPerRowOfPlane(buffer, plane) * CVPixelBufferGetHeightOfPlane(buffer, plane))
        }
      }
      CVPixelBufferUnlockBaseAddress(buffer, [])
      let encodeStatus = VTCompressionSessionEncodeFrame(
        session, imageBuffer: buffer, presentationTimeStamp: CMTime(value: Int64(index), timescale: 15), duration: .invalid,
        frameProperties: index == 0 ? [kVTEncodeFrameOptionKey_ForceKeyFrame as String: true] as CFDictionary : nil, infoFlagsOut: nil
      ) { status, flags, sample in
        encoded.withLockUnchecked {
          if status != noErr {
            $0.failures.append("frame \(index): status \(status)")
          } else if flags.contains(.frameDropped) {
            $0.failures.append("frame \(index): dropped")
          } else if let sample {
            $0.samples.append(sample)
          } else {
            $0.failures.append("frame \(index): no sample")
          }
        }
      }
      #expect(encodeStatus == noErr)
    }
    #expect(VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid) == noErr)
    let result = encoded.withLockUnchecked { $0 }
    #expect(result.failures.isEmpty, "\(result.failures)")
    #expect(result.samples.count == frameCount)
    return result.samples
  }

  @Test(arguments: [kCMVideoCodecType_H264, kCMVideoCodecType_HEVC])
  func aSoftwareEncodersFirstSampleIsAKeyFrameTheWebMWriterAccepts(codec: CMVideoCodecType) throws {
    let samples = try softwareSamples(codec: codec)
    let first = try #require(samples.first)
    #expect(first.isKeyFrame)
    #expect(samples.dropFirst().contains { !$0.isKeyFrame })

    let writer = WebMFileWriter(fileURL: fileURL)
    var written = 0
    for sample in samples where try writer.write(sample) {
      written += 1
    }
    try writer.finish()
    #expect(written == samples.count)
    #expect(try Data(contentsOf: fileURL).count > 0)
  }
}
