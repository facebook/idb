/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreVideo
@testable import FBSimulatorControl
import VideoToolbox
import XCTest

final class PixelBufferConverterTests: XCTestCase {

  func testEncoderConverterTellsTheTransferSessionNoDestinationColor() throws {
    let converter = try PixelBufferConverter(outputWidth: 64, outputHeight: 64, pixelFormat: PixelBufferConverter.encoderPixelFormat)
    defer { converter.invalidate() }
    // BUG: the BGRA→NV12 conversion runs on VideoToolbox's default matrix for the frame size, so
    // what the encoder is fed is not necessarily what the bitstream will claim — flipped to an
    // explicit BT.709 destination in the following commit.
    XCTAssertEqual(converter.destinationColorProperties, [:])
  }

  func testBitmapConverterTellsTheTransferSessionNoDestinationColor() throws {
    let converter = try PixelBufferConverter(outputWidth: 64, outputHeight: 64, pixelFormat: kCVPixelFormatType_32BGRA)
    defer { converter.invalidate() }
    XCTAssertEqual(converter.destinationColorProperties, [:])
  }

  func testConverterProducesTheRequestedFormatAndSize() throws {
    let converter = try PixelBufferConverter(outputWidth: 32, outputHeight: 16, pixelFormat: PixelBufferConverter.encoderPixelFormat)
    defer { converter.invalidate() }
    var source: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(nil, 64, 32, kCVPixelFormatType_32BGRA, nil, &source), kCVReturnSuccess)
    guard case let .converted(destination) = converter.convert(source!) else {
      return XCTFail("Expected a converted buffer")
    }
    XCTAssertEqual(CVPixelBufferGetWidth(destination), 32)
    XCTAssertEqual(CVPixelBufferGetHeight(destination), 16)
    XCTAssertEqual(CVPixelBufferGetPixelFormatType(destination), PixelBufferConverter.encoderPixelFormat)
  }
}
