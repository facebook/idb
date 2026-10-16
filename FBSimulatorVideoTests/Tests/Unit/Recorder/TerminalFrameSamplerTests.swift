/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreVideo
import FBSimulatorVideo
import IOSurface
import Testing

/// A surface whose four quadrants are filled with the given RGB colours.
private func quadrantSurface(
  pixelFormat: OSType = kCVPixelFormatType_32BGRA,
  topLeft: SIMD4<UInt8>, topRight: SIMD4<UInt8>, bottomLeft: SIMD4<UInt8>, bottomRight: SIMD4<UInt8>
) throws -> IOSurface {
  let size = 8
  let surface = try #require(
    IOSurface(properties: [.width: size, .height: size, .bytesPerElement: 4, .pixelFormat: pixelFormat]))
  surface.lock(options: [], seed: nil)
  defer { surface.unlock(options: [], seed: nil) }
  let bytesPerRow = surface.bytesPerRow
  let base = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
  for y in 0..<size {
    for x in 0..<size {
      let c = y < size / 2 ? (x < size / 2 ? topLeft : topRight) : (x < size / 2 ? bottomLeft : bottomRight)
      let pixel = base + y * bytesPerRow + x * 4
      pixel[0] = c.z
      pixel[1] = c.y
      pixel[2] = c.x
      pixel[3] = 255
    }
  }
  return surface
}

private let red = SIMD4<UInt8>(255, 0, 0, 255)
private let green = SIMD4<UInt8>(0, 255, 0, 255)
private let blue = SIMD4<UInt8>(0, 0, 255, 255)
private let white = SIMD4<UInt8>(255, 255, 255, 255)

@Suite struct TerminalFrameSamplerTests {
  @Test func samplesTopAndBottomHalvesOfEachCell() throws {
    let sampler = try TerminalFrameSampler()
    try sampler.attach(quadrantSurface(topLeft: red, topRight: green, bottomLeft: blue, bottomRight: white))
    let cells = try #require(try sampler.sample(grid: TerminalGrid(columns: 2, rows: 1)))
    #expect(cells == [TerminalCell(top: red, bottom: blue), TerminalCell(top: green, bottom: white)])
  }

  @Test func averagesPixelsWithinACell() throws {
    let sampler = try TerminalFrameSampler()
    try sampler.attach(quadrantSurface(topLeft: red, topRight: blue, bottomLeft: red, bottomRight: blue))
    let cells = try #require(try sampler.sample(grid: TerminalGrid(columns: 1, rows: 1)))
    let purple = SIMD4<UInt8>(128, 0, 128, 255)
    #expect(cells == [TerminalCell(top: purple, bottom: purple)])
  }

  @Test func quantizesChannels() throws {
    let sampler = try TerminalFrameSampler(colorBits: 1)
    let dim = SIMD4<UInt8>(100, 100, 100, 255)
    let bright = SIMD4<UInt8>(156, 156, 156, 255)
    try sampler.attach(quadrantSurface(topLeft: dim, topRight: dim, bottomLeft: bright, bottomRight: bright))
    let cells = try #require(try sampler.sample(grid: TerminalGrid(columns: 1, rows: 1)))
    #expect(cells == [TerminalCell(top: SIMD4(0, 0, 0, 255), bottom: white)])
  }

  @Test func samplesNothingWithoutASurface() throws {
    let sampler = try TerminalFrameSampler()
    try sampler.attach(nil)
    #expect(try sampler.sample(grid: TerminalGrid(columns: 2, rows: 1)) == nil)
    #expect(sampler.surfaceSize == nil)
  }

  @Test func rejectsNonBGRASurfaces() throws {
    let sampler = try TerminalFrameSampler()
    let surface = try quadrantSurface(pixelFormat: kCVPixelFormatType_32ARGB, topLeft: red, topRight: red, bottomLeft: red, bottomRight: red)
    #expect(throws: TerminalFrameSamplerError.self) { try sampler.attach(surface) }
  }
}
