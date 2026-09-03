/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBDeviceControl
import Foundation
import Testing

// Constants mirroring private definitions in FBInstrumentsClient.
private let TestArgumentMagic: UInt64 = 0x1F0
private let TestEmptyDictionaryKey: UInt32 = 10
private let TestObjectArgumentType: UInt32 = 2
private let TestInt32ArgumentType: UInt32 = 3

private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
  var value: UInt32 = 0
  withUnsafeMutableBytes(of: &value) { destination in
    destination.copyBytes(from: data.subdata(in: offset..<(offset + 4)))
  }
  return value
}

private func readInt32(_ data: Data, at offset: Int) -> Int32 {
  Int32(bitPattern: readUInt32(data, at: offset))
}

private func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
  var value: UInt64 = 0
  withUnsafeMutableBytes(of: &value) { destination in
    destination.copyBytes(from: data.subdata(in: offset..<(offset + 8)))
  }
  return value
}

/// The DTX argument wire format: what goes out for each argument kind, and that the auxillary
/// framing round-trips.
@Suite
struct FBInstrumentsClientTests {

  // MARK: - Object arguments

  @Test
  func argumentDataForStringProducesValidSerializedData() throws {
    let argument = "com.example.testapp"

    let result = FBInstrumentsClient.argumentData(forArgument: argument)

    #expect(result.count > 12, "Result should be larger than the 12-byte header")
    #expect(readUInt32(result, at: 0) == TestEmptyDictionaryKey)
    #expect(readUInt32(result, at: 4) == TestObjectArgumentType)
    let argumentSize = readUInt32(result, at: 8)
    #expect(Int(argumentSize) == result.count - 12, "Argument size should match remaining data length")

    let archived = result.subdata(in: 12..<(12 + Int(argumentSize)))
    let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSString.self, from: archived)
    #expect(decoded as String? == argument)
  }

  @Test
  func argumentDataForDictionaryProducesValidSerializedData() throws {
    let argument: [String: Bool] = ["StartSuspendedKey": true, "KillExisting": false]

    let result = FBInstrumentsClient.argumentData(forArgument: argument)

    #expect(result.count > 12)
    let argumentSize = readUInt32(result, at: 8)
    let archived = result.subdata(in: 12..<(12 + Int(argumentSize)))
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClasses: [NSDictionary.self, NSNumber.self, NSString.self], from: archived)
    #expect(decoded as? [String: Bool] == argument)
  }

  @Test
  func argumentDataForEmptyStringProducesValidSerializedData() throws {
    let result = FBInstrumentsClient.argumentData(forArgument: "")

    #expect(result.count > 12)
    let argumentSize = readUInt32(result, at: 8)
    let archived = result.subdata(in: 12..<(12 + Int(argumentSize)))
    let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSString.self, from: archived)
    #expect(decoded as String? == "")
  }

  // MARK: - Int32 arguments

  @Test
  func argumentDataForInt32WithPositiveValueProducesCorrectFormat() {
    let result = FBInstrumentsClient.argumentData(forInt32: 42)

    #expect(result.count == 12, "Int32 argument data should be exactly 12 bytes")
    #expect(readUInt32(result, at: 0) == TestEmptyDictionaryKey)
    #expect(readUInt32(result, at: 4) == TestInt32ArgumentType)
    #expect(readInt32(result, at: 8) == 42)
  }

  @Test
  func argumentDataForInt32WithNegativeValuePreservesSign() {
    let result = FBInstrumentsClient.argumentData(forInt32: -1)

    #expect(result.count == 12)
    #expect(readInt32(result, at: 8) == -1)
  }

  @Test
  func argumentDataForInt32WithZeroProducesCorrectFormat() {
    let result = FBInstrumentsClient.argumentData(forInt32: 0)

    #expect(result.count == 12)
    #expect(readInt32(result, at: 8) == 0)
  }

  @Test
  func argumentDataForInt32WithMaxValuePreservesBoundary() {
    let result = FBInstrumentsClient.argumentData(forInt32: Int32.max)

    #expect(readInt32(result, at: 8) == Int32.max)
  }

  // MARK: - Auxillary framing

  @Test
  func auxillaryDataFromNilArgumentsReturnsEmptyData() {
    let result = FBInstrumentsClient.auxillaryData(fromArgumentsData: nil)

    #expect(result.isEmpty, "Nil arguments should produce empty data")
  }

  @Test
  func auxillaryDataFromSingleArgumentIncludesMagicAndLength() {
    let argData = FBInstrumentsClient.argumentData(forArgument: "test")

    let result = FBInstrumentsClient.auxillaryData(fromArgumentsData: [argData])

    #expect(result.count == 16 + argData.count, "Result should be header (16) + argument data")
    #expect(readUInt64(result, at: 0) == TestArgumentMagic)
    #expect(readUInt64(result, at: 8) == UInt64(argData.count))
  }

  @Test
  func auxillaryDataFromMultipleArgumentsConcatenatesCorrectly() {
    let arg1 = FBInstrumentsClient.argumentData(forArgument: "first")
    let arg2 = FBInstrumentsClient.argumentData(forArgument: "second")

    let result = FBInstrumentsClient.auxillaryData(fromArgumentsData: [arg1, arg2])

    #expect(readUInt64(result, at: 8) == UInt64(arg1.count + arg2.count))
    #expect(result.count == 16 + arg1.count + arg2.count)
  }

  @Test
  func auxillaryDataFromEmptyArrayProducesHeaderOnly() {
    let result = FBInstrumentsClient.auxillaryData(fromArgumentsData: [])

    #expect(result.count == 16, "Empty array should produce header-only data (16 bytes)")
    #expect(readUInt64(result, at: 8) == 0)
  }

  // MARK: - Round trips

  @Test
  func objectArgumentsRoundTripWithSingleString() throws {
    let argData = FBInstrumentsClient.argumentData(forArgument: "hello")
    let auxData = FBInstrumentsClient.auxillaryData(fromArgumentsData: [argData])

    let result = try FBInstrumentsClient.objectArguments(fromAuxillaryData: auxData)

    #expect(result.count == 1)
    #expect(result.first as? String == "hello")
  }

  @Test
  func objectArgumentsRoundTripWithMultipleArguments() throws {
    let arg1 = FBInstrumentsClient.argumentData(forArgument: "first")
    let arg2 = FBInstrumentsClient.argumentData(forArgument: 42)
    let auxData = FBInstrumentsClient.auxillaryData(fromArgumentsData: [arg1, arg2])

    let result = try FBInstrumentsClient.objectArguments(fromAuxillaryData: auxData)

    #expect(result.count == 2)
    #expect(result.first as? String == "first")
    #expect(result.last as? Int == 42)
  }

  @Test
  func objectArgumentsWithInsufficientDataThrows() {
    let shortData = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])

    #expect(throws: (any Error).self) {
      try FBInstrumentsClient.objectArguments(fromAuxillaryData: shortData)
    }
  }

  @Test
  func objectArgumentsRoundTripWithDictionary() throws {
    let dictionary: [String: Any] = ["key": "value", "number": 123]
    let argData = FBInstrumentsClient.argumentData(forArgument: dictionary)
    let auxData = FBInstrumentsClient.auxillaryData(fromArgumentsData: [argData])

    let result = try FBInstrumentsClient.objectArguments(fromAuxillaryData: auxData)

    #expect(result.count == 1)
    let decoded = result.first as? NSDictionary
    #expect(decoded == dictionary as NSDictionary)
  }

  // MARK: - The advanceData compatibility walkers

  @Test
  func advanceDataWithBufferReadsCorrectBytesAndAdvances() {
    let values: [UInt32] = [0xDEAD_BEEF, 0xCAFE_BABE, 0x1234_5678]
    let data = values.withUnsafeBytes { Data($0) }

    var firstValue: UInt32 = 0
    let remaining = withUnsafeMutableBytes(of: &firstValue) { buffer in
      FBInstrumentsClient.advance(data, buffer: buffer.baseAddress!, length: 4)
    }

    #expect(firstValue == 0xDEAD_BEEF)
    #expect(remaining.count == 8)

    var secondValue: UInt32 = 0
    let remaining2 = withUnsafeMutableBytes(of: &secondValue) { buffer in
      FBInstrumentsClient.advance(remaining, buffer: buffer.baseAddress!, length: 4)
    }
    #expect(secondValue == 0xCAFE_BABE)
    #expect(remaining2.count == 4)
  }

  @Test
  func advanceDataWithDataOutExtractsSubdataAndAdvances() {
    let data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])

    var extracted: NSData?
    let remaining = FBInstrumentsClient.advance(data, dataOut: &extracted, length: 3)

    #expect(extracted as Data? == Data([0x01, 0x02, 0x03]))
    #expect(remaining.count == 5)
  }

  @Test
  func advanceDataWithNilDataOutStillAdvances() {
    let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])

    let remaining = FBInstrumentsClient.advance(data, dataOut: nil, length: 2)

    #expect(remaining.count == 3, "Should advance past 2 bytes even with nil dataOut")
  }

  @Test
  func objectArgumentsPreservesArgumentOrder() throws {
    let auxData = FBInstrumentsClient.auxillaryData(fromArgumentsData: [
      FBInstrumentsClient.argumentData(forArgument: "alpha"),
      FBInstrumentsClient.argumentData(forArgument: "beta"),
      FBInstrumentsClient.argumentData(forArgument: "gamma"),
    ])

    let result = try FBInstrumentsClient.objectArguments(fromAuxillaryData: auxData)

    #expect(result.count == 3)
    #expect(result.first as? String == "alpha")
    #expect(result.dropFirst().first as? String == "beta")
    #expect(result.last as? String == "gamma")
  }
}
