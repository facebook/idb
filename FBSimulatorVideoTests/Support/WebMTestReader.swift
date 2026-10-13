/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import Foundation

/// Reads back what a WebM recording holds: its DocType, its blocks in order, and its chapter titles.
struct WebMTestReader {
  struct Block {
    let isKeyFrame: Bool
    let frame: [UInt8]
  }

  struct ReadError: Error {
    let message: String
  }

  private struct Element {
    let id: UInt32
    let data: Range<Int>
  }

  let docType: String
  let blocks: [Block]
  let chapterTitles: [String]

  init(path: String) throws {
    let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
    let top = try Self.elements(bytes, in: 0..<bytes.count)
    guard top.count == 2, let header = top.first(where: { $0.id == 0x1A45_DFA3 }), let segment = top.first(where: { $0.id == 0x1853_8067 }) else {
      throw ReadError(message: "expected an EBML header and a segment")
    }
    let docType = try Self.elements(bytes, in: header.data).first { $0.id == 0x4282 }
    self.docType = docType.map { String(decoding: bytes[$0.data], as: UTF8.self) } ?? ""
    let children = try Self.elements(bytes, in: segment.data)
    blocks = try children.filter { $0.id == 0x1F43_B675 }.flatMap { cluster in
      try Self.elements(bytes, in: cluster.data).filter { $0.id == 0xA3 }.map { block in
        Block(isKeyFrame: bytes[block.data.lowerBound + 3] & 0x80 != 0, frame: Array(bytes[(block.data.lowerBound + 4)..<block.data.upperBound]))
      }
    }
    var titles: [String] = []
    for chapters in children where chapters.id == 0x1043_A770 {
      for edition in try Self.elements(bytes, in: chapters.data) where edition.id == 0x45B9 {
        for atom in try Self.elements(bytes, in: edition.data) where atom.id == 0xB6 {
          for display in try Self.elements(bytes, in: atom.data) where display.id == 0x80 {
            for string in try Self.elements(bytes, in: display.data) where string.id == 0x85 {
              titles.append(String(decoding: bytes[string.data], as: UTF8.self))
            }
          }
        }
      }
    }
    chapterTitles = titles
  }

  /// The frame size each keyframe's leading H.264 parameter sets describe, in order.
  func keyFrameDimensions() throws -> [CMVideoDimensions] {
    try blocks.filter(\.isKeyFrame).map { block in
      var nalUnits: [[UInt8]] = []
      var position = 0
      while position + 4 <= block.frame.count, nalUnits.count < 2 {
        let length = block.frame[position..<position + 4].reduce(0) { $0 << 8 | Int($1) }
        nalUnits.append(Array(block.frame[(position + 4)..<min(position + 4 + length, block.frame.count)]))
        position += 4 + length
      }
      guard nalUnits.count == 2, nalUnits[0].first.map({ $0 & 0x1F }) == 7 else {
        throw ReadError(message: "a keyframe without leading SPS and PPS")
      }
      var format: CMFormatDescription?
      let status = nalUnits[0].withUnsafeBufferPointer { sps in
        nalUnits[1].withUnsafeBufferPointer { pps in
          let pointers = [sps.baseAddress!, pps.baseAddress!]
          let sizes = [sps.count, pps.count]
          return CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: nil, parameterSetCount: 2, parameterSetPointers: pointers, parameterSetSizes: sizes, nalUnitHeaderLength: 4,
            formatDescriptionOut: &format)
        }
      }
      guard status == noErr, let format else {
        throw ReadError(message: "parameter sets CoreMedia refuses: \(status)")
      }
      return CMVideoFormatDescriptionGetDimensions(format)
    }
  }

  private static func elements(_ bytes: [UInt8], in range: Range<Int>) throws -> [Element] {
    var elements: [Element] = []
    var position = range.lowerBound
    while position < range.upperBound {
      let idLength = bytes[position].leadingZeroBitCount + 1
      guard idLength <= 4, position + idLength < range.upperBound else {
        throw ReadError(message: "a malformed element ID at \(position)")
      }
      let id = bytes[position..<position + idLength].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
      position += idLength
      let sizeLength = bytes[position].leadingZeroBitCount + 1
      guard sizeLength <= 8, position + sizeLength <= range.upperBound else {
        throw ReadError(message: "a malformed element size at \(position)")
      }
      var size = UInt64(bytes[position] & (0xFF >> sizeLength))
      var allOnes = size == UInt64(0xFF >> sizeLength)
      for byte in bytes[(position + 1)..<(position + sizeLength)] {
        size = size << 8 | UInt64(byte)
        allOnes = allOnes && byte == 0xFF
      }
      position += sizeLength
      let end = allOnes ? range.upperBound : position + Int(size)
      guard end <= range.upperBound else {
        throw ReadError(message: "element \(String(id, radix: 16)) overruns its parent")
      }
      elements.append(Element(id: id, data: position..<end))
      position = end
    }
    return elements
  }
}
