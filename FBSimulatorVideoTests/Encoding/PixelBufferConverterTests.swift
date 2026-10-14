/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreVideo
@testable import FBSimulatorControl
@testable import FBSimulatorVideo
import Foundation
import Testing
import VideoToolbox

@Suite
struct PixelBufferConverterTests {

  @Test
  func encoderConverterTellsTheTransferSessionItsDestinationColor() throws {
    let converter = try PixelBufferConverter(outputWidth: 64, outputHeight: 64, pixelFormat: PixelBufferConverter.encoderPixelFormat, destinationColor: .sRGB)
    defer { converter.invalidate() }
    #expect(
      converter.destinationColorProperties == [
        kVTPixelTransferPropertyKey_DestinationColorPrimaries as String: kCVImageBufferColorPrimaries_ITU_R_709_2 as String,
        kVTPixelTransferPropertyKey_DestinationTransferFunction as String: kCVImageBufferTransferFunction_sRGB as String,
        kVTPixelTransferPropertyKey_DestinationYCbCrMatrix as String: kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String,
      ])
  }

  @Test
  func bitmapConverterTellsTheTransferSessionNoDestinationColor() throws {
    let converter = try PixelBufferConverter(outputWidth: 64, outputHeight: 64, pixelFormat: kCVPixelFormatType_32BGRA)
    defer { converter.invalidate() }
    #expect(converter.destinationColorProperties == [:])
  }

  @Test
  func converterProducesTheRequestedFormatAndSize() throws {
    let converter = try PixelBufferConverter(outputWidth: 32, outputHeight: 16, pixelFormat: PixelBufferConverter.encoderPixelFormat)
    defer { converter.invalidate() }
    var source: CVPixelBuffer?
    let status = CVPixelBufferCreate(nil, 64, 32, kCVPixelFormatType_32BGRA, nil, &source)
    #expect(status == kCVReturnSuccess)
    guard case let .converted(destination) = converter.convert(try #require(source)) else {
      Issue.record("Expected a converted buffer")
      return
    }
    #expect(CVPixelBufferGetWidth(destination) == 32)
    #expect(CVPixelBufferGetHeight(destination) == 16)
    #expect(CVPixelBufferGetPixelFormatType(destination) == PixelBufferConverter.encoderPixelFormat)
  }
}
