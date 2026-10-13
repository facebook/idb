/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
@testable import FBVideoCore
import XCTest

/// EBML element encoding (`EBML`) and the WebM file writer built on it, read back with a minimal EBML reader.
final class WebMFileWriterTests: XCTestCase {

  private var fileURL: URL!

  override func setUp() {
    super.setUp()
    fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).webm")
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: fileURL)
    super.tearDown()
  }

  // MARK: - EBML

  func testSizesUseTheShortestEncodingThatAvoidsTheUnknownMarker() {
    XCTAssertEqual(EBML.size(0), [0x80])
    XCTAssertEqual(EBML.size(126), [0xFE])
    XCTAssertEqual(EBML.size(127), [0x40, 0x7F])
    XCTAssertEqual(EBML.size(16382), [0x7F, 0xFE])
    XCTAssertEqual(EBML.size(16383), [0x20, 0x3F, 0xFF])
    XCTAssertEqual(EBML.size(5, length: 8), [0x01, 0, 0, 0, 0, 0, 0, 0x05])
  }

  func testIDsAreTheirSignificantBytes() {
    XCTAssertEqual(EBML.id(0xEC), [0xEC])
    XCTAssertEqual(EBML.id(0x4489), [0x44, 0x89])
    XCTAssertEqual(EBML.id(0x2A_D7B1), [0x2A, 0xD7, 0xB1])
    XCTAssertEqual(EBML.id(0x1A45_DFA3), [0x1A, 0x45, 0xDF, 0xA3])
  }

  func testAVoidFillsExactlyTheSpaceAskedFor() throws {
    for size in [2, 11, 128, 129, 200] {
      var writer = EBML.Writer()
      writer.void(totalSize: size)
      XCTAssertEqual(writer.count, size)
      let elements = try readElements(writer.data, in: 0..<writer.count)
      XCTAssertEqual(elements.map(\.id), [WebM.ID.void])
      XCTAssertEqual(elements.first?.range.upperBound, size)
    }
  }

  // MARK: - File

  func testAFinishedRecordingHasItsTrackClustersCuesChaptersAndDuration() throws {
    let writer = WebMFileWriter(fileURL: fileURL)
    let first = makeH264SampleBuffer(isKeyFrame: true, pts90k: 900_000)
    XCTAssertTrue(try writer.write(first))
    XCTAssertTrue(try writer.write(makeH264SampleBuffer(isKeyFrame: false, pts90k: 900_000 + 2970)))
    XCTAssertTrue(try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 900_000 + 225_000)))
    XCTAssertTrue(try writer.write(makeH264SampleBuffer(isKeyFrame: false, pts90k: 900_000 + 227_970)))
    try writer.finish(chapters: [
      (title: "portrait", time: CMTime(value: 900_000, timescale: 90000)),
      (title: "landscape", time: CMTime(value: 900_000 + 225_000, timescale: 90000)),
    ])
    XCTAssertEqual(writer.startPresentationTime, CMTime(value: 900_000, timescale: 90000))

    let file = try WebMFile(fileURL)
    XCTAssertEqual(file.docType, "webm")
    XCTAssertFalse(file.segmentSizeIsUnknown)
    XCTAssertEqual(
      file.segmentChildren.map(\.id),
      [WebM.ID.seekHead, WebM.ID.void, WebM.ID.info, WebM.ID.tracks, WebM.ID.cluster, WebM.ID.cluster, WebM.ID.cues, WebM.ID.chapters])

    let info = try file.child(WebM.ID.info)
    XCTAssertEqual(try file.uint(WebM.ID.timestampScale, in: info), 1_000_000)
    XCTAssertEqual(try file.float(WebM.ID.duration, in: info), 2533 + 33)

    let track = try file.child(WebM.ID.trackEntry, in: try file.child(WebM.ID.tracks))
    XCTAssertEqual(try file.string(WebM.ID.codecID, in: track), "V_MPEG4/ISO/AVC")
    XCTAssertEqual(try file.bytes(WebM.ID.codecPrivate, in: track).first, 1, "an avcC record begins with its version")
    let dimensions = CMVideoFormatDescriptionGetDimensions(try XCTUnwrap(CMSampleBufferGetFormatDescription(first)))
    let video = try file.child(WebM.ID.video, in: track)
    XCTAssertEqual(try file.uint(WebM.ID.pixelWidth, in: video), UInt64(dimensions.width))
    XCTAssertEqual(try file.uint(WebM.ID.pixelHeight, in: video), UInt64(dimensions.height))

    let clusters = file.segmentChildren.filter { $0.id == WebM.ID.cluster }
    XCTAssertEqual(try clusters.map { try file.uint(WebM.ID.timestamp, in: $0) }, [0, 2500])
    XCTAssertEqual(try clusters.flatMap { try file.blocks(in: $0).map(\.relativeTime) }, [0, 33, 0, 33])
    XCTAssertEqual(try clusters.flatMap { try file.blocks(in: $0).map(\.isKeyFrame) }, [true, false, true, false])

    let cuePoints = try file.children(WebM.ID.cuePoint, in: try file.child(WebM.ID.cues))
    XCTAssertEqual(try cuePoints.map { try file.uint(WebM.ID.cueTime, in: $0) }, [0, 2500])
    for cuePoint in cuePoints {
      let position = try file.uint(WebM.ID.cueClusterPosition, in: try file.child(WebM.ID.cueTrackPositions, in: cuePoint))
      XCTAssertEqual(try file.element(atSegmentPosition: position).id, WebM.ID.cluster)
    }

    let seeks = try file.children(WebM.ID.seek, in: try file.child(WebM.ID.seekHead))
    for seek in seeks {
      let id = try file.bytes(WebM.ID.seekID, in: seek).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
      XCTAssertEqual(try file.element(atSegmentPosition: try file.uint(WebM.ID.seekPosition, in: seek)).id, id)
    }
    XCTAssertEqual(seeks.count, 4)

    let atoms = try file.children(WebM.ID.chapterAtom, in: try file.child(WebM.ID.editionEntry, in: try file.child(WebM.ID.chapters)))
    XCTAssertEqual(try atoms.map { try file.string(WebM.ID.chapString, in: try file.child(WebM.ID.chapterDisplay, in: $0)) }, ["portrait", "landscape"])
    XCTAssertEqual(try atoms.map { try file.uint(WebM.ID.chapterTimeStart, in: $0) }, [0, 2_500_000_000])
    XCTAssertEqual(try atoms.map { try file.uint(WebM.ID.chapterTimeEnd, in: $0) }, [2_500_000_000, 2_566_000_000])
  }

  func testEveryKeyFrameCarriesItsOwnParameterSets() throws {
    let writer = WebMFileWriter(fileURL: fileURL)
    try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 0))
    try writer.write(makeH264SampleBuffer(isKeyFrame: false, pts90k: 3000))
    try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 6000, sps: alternateTestSPS))
    try writer.finish()

    let file = try WebMFile(fileURL)
    let codecPrivate = try file.bytes(WebM.ID.codecPrivate, in: try file.child(WebM.ID.trackEntry, in: try file.child(WebM.ID.tracks)))
    XCTAssertTrue(codecPrivate.containsSubsequence(defaultTestSPS), "the track is configured from the first keyframe")
    let frames = try file.segmentChildren.filter { $0.id == WebM.ID.cluster }.flatMap { try file.blocks(in: $0).map(\.frame) }
    XCTAssertEqual(frames.count, 3)
    XCTAssertEqual(Array(frames[0].prefix(4 + defaultTestSPS.count)), lengthPrefixed(defaultTestSPS))
    XCTAssertEqual(frames[1], defaultTestAVCCBytes, "a delta frame is the encoder's data alone")
    XCTAssertEqual(Array(frames[2].prefix(4 + alternateTestSPS.count)), lengthPrefixed(alternateTestSPS))
    XCTAssertEqual(Array(frames[2].suffix(defaultTestAVCCBytes.count)), defaultTestAVCCBytes)
  }

  func testAnUnfinishedRecordingKeepsItsCompleteClusters() throws {
    let writer = WebMFileWriter(fileURL: fileURL)
    try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 0))
    try writer.write(makeH264SampleBuffer(isKeyFrame: false, pts90k: 3000))
    try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 225_000))

    let file = try WebMFile(fileURL)
    XCTAssertTrue(file.segmentSizeIsUnknown)
    XCTAssertEqual(file.segmentChildren.map(\.id), [WebM.ID.void, WebM.ID.info, WebM.ID.tracks, WebM.ID.cluster])
    XCTAssertEqual(try file.children(WebM.ID.duration, in: try file.child(WebM.ID.info)).count, 0, "an unknown duration is left out, not written as zero")
    XCTAssertEqual(try file.blocks(in: try file.child(WebM.ID.cluster)).count, 2)
    withExtendedLifetime(writer) {}
  }

  func testFramesBeforeTheFirstKeyFrameAreDropped() throws {
    let writer = WebMFileWriter(fileURL: fileURL)
    XCTAssertFalse(try writer.write(makeH264SampleBuffer(isKeyFrame: false, pts90k: 0)))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    XCTAssertNil(writer.startPresentationTime)

    XCTAssertTrue(try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 3000)))
    try writer.finish()
    let file = try WebMFile(fileURL)
    XCTAssertEqual(try file.blocks(in: try file.child(WebM.ID.cluster)).map(\.relativeTime), [0])
  }

  func testAFinishedFileTakesNoMoreSamples() throws {
    let writer = WebMFileWriter(fileURL: fileURL)
    try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 0))
    try writer.finish()
    let finished = try Data(contentsOf: fileURL)

    XCTAssertThrowsError(try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 3000)))
    XCTAssertNoThrow(try writer.finish(), "a second finish has nothing left to do")
    XCTAssertEqual(try Data(contentsOf: fileURL), finished)
  }

  func testAFileFinishedBeforeItsFirstKeyFrameTakesNoMoreSamples() throws {
    let writer = WebMFileWriter(fileURL: fileURL)
    try writer.finish()

    XCTAssertThrowsError(try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 0)))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
  }

  func testAClusterEndsBeforeABlockOffsetWouldOverflow() throws {
    let writer = WebMFileWriter(fileURL: fileURL)
    try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 0))
    try writer.write(makeH264SampleBuffer(isKeyFrame: false, pts90k: 31 * 90000))
    try writer.finish()

    let file = try WebMFile(fileURL)
    let clusters = file.segmentChildren.filter { $0.id == WebM.ID.cluster }
    XCTAssertEqual(try clusters.map { try file.uint(WebM.ID.timestamp, in: $0) }, [0, 31000])
    XCTAssertEqual(try file.children(WebM.ID.cuePoint, in: try file.child(WebM.ID.cues)).count, 1, "only a keyframe cluster is a cue")
  }

  func testHEVCIsLabelledWithItsMatroskaCodecID() throws {
    let sampleBuffer = try XCTUnwrap(makeHEVCSampleBuffer(isKeyFrame: true))
    let writer = WebMFileWriter(fileURL: fileURL)
    try writer.write(sampleBuffer)
    try writer.finish()

    let file = try WebMFile(fileURL)
    let track = try file.child(WebM.ID.trackEntry, in: try file.child(WebM.ID.tracks))
    XCTAssertEqual(try file.string(WebM.ID.codecID, in: track), "V_MPEGH/ISO/HEVC")
    let frame = try XCTUnwrap(try file.blocks(in: try file.child(WebM.ID.cluster)).first?.frame)
    XCTAssertEqual(Array(frame.prefix(4 + hevcVPS.count)), lengthPrefixed(hevcVPS))
  }

  func testAnotherCodecIsRefused() throws {
    let writer = WebMFileWriter(fileURL: fileURL)
    XCTAssertThrowsError(try writer.write(makeJPEGSampleBuffer(bytes: [0xFF, 0xD8, 0xFF, 0xD9], width: 2, height: 2)))
  }

  private func lengthPrefixed(_ bytes: [UInt8]) -> [UInt8] {
    withUnsafeBytes(of: UInt32(bytes.count).bigEndian) { Array($0) } + bytes
  }
}

// MARK: - Reading EBML back

private struct EBMLElement {
  let id: UInt32
  /// The element's data.
  let data: Range<Int>
  /// The whole element, header included.
  let range: Range<Int>
  let sizeIsUnknown: Bool
}

private struct EBMLReadError: Error {
  let message: String
}

/// The elements in `range`, in order. An element of unknown size runs to the end of the range.
private func readElements(_ bytes: [UInt8], in range: Range<Int>) throws -> [EBMLElement] {
  var elements: [EBMLElement] = []
  var position = range.lowerBound
  while position < range.upperBound {
    let start = position
    let idLength = bytes[position].leadingZeroBitCount + 1
    guard idLength <= 4, position + idLength <= range.upperBound else { throw EBMLReadError(message: "bad ID at \(position)") }
    let id = bytes[position..<position + idLength].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    position += idLength
    let sizeLength = bytes[position].leadingZeroBitCount + 1
    guard sizeLength <= 8, position + sizeLength <= range.upperBound else { throw EBMLReadError(message: "bad size at \(position)") }
    var size = UInt64(bytes[position] & (0xFF >> sizeLength))
    var allOnes = size == UInt64(0xFF >> sizeLength)
    for byte in bytes[position + 1..<position + sizeLength] {
      size = size << 8 | UInt64(byte)
      allOnes = allOnes && byte == 0xFF
    }
    position += sizeLength
    let end = allOnes ? range.upperBound : position + Int(size)
    guard end <= range.upperBound else { throw EBMLReadError(message: "element \(String(id, radix: 16)) overruns its parent") }
    elements.append(EBMLElement(id: id, data: position..<end, range: start..<end, sizeIsUnknown: allOnes))
    position = end
  }
  return elements
}

private struct WebMBlock {
  let relativeTime: Int16
  let isKeyFrame: Bool
  let frame: [UInt8]
}

private struct WebMFile {
  let bytes: [UInt8]
  let docType: String
  let segment: EBMLElement
  let segmentChildren: [EBMLElement]

  var segmentSizeIsUnknown: Bool {
    segment.sizeIsUnknown
  }

  init(_ url: URL) throws {
    bytes = [UInt8](try Data(contentsOf: url))
    let top = try readElements(bytes, in: 0..<bytes.count)
    guard top.count == 2, top[0].id == WebM.ID.ebml, top[1].id == WebM.ID.segment else {
      throw EBMLReadError(message: "expected an EBML header and a segment, found \(top.map { String($0.id, radix: 16) })")
    }
    let header = try readElements(bytes, in: top[0].data)
    guard let docType = header.first(where: { $0.id == WebM.ID.docType }) else { throw EBMLReadError(message: "no DocType") }
    self.docType = String(decoding: bytes[docType.data], as: UTF8.self)
    segment = top[1]
    segmentChildren = try readElements(bytes, in: segment.data)
  }

  func children(_ id: UInt32, in parent: EBMLElement) throws -> [EBMLElement] {
    try readElements(bytes, in: parent.data).filter { $0.id == id }
  }

  func child(_ id: UInt32, in parent: EBMLElement? = nil) throws -> EBMLElement {
    let candidates = try parent.map { try children(id, in: $0) } ?? segmentChildren.filter { $0.id == id }
    guard let element = candidates.first else { throw EBMLReadError(message: "no element \(String(id, radix: 16))") }
    return element
  }

  func bytes(_ id: UInt32, in parent: EBMLElement) throws -> [UInt8] {
    Array(bytes[try child(id, in: parent).data])
  }

  func uint(_ id: UInt32, in parent: EBMLElement) throws -> UInt64 {
    try bytes(id, in: parent).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
  }

  func float(_ id: UInt32, in parent: EBMLElement) throws -> Double {
    Double(bitPattern: try uint(id, in: parent))
  }

  func string(_ id: UInt32, in parent: EBMLElement) throws -> String {
    String(decoding: try bytes(id, in: parent), as: UTF8.self)
  }

  func element(atSegmentPosition position: UInt64) throws -> EBMLElement {
    guard let element = segmentChildren.first(where: { $0.range.lowerBound == segment.data.lowerBound + Int(position) }) else {
      throw EBMLReadError(message: "no segment child at position \(position)")
    }
    return element
  }

  func blocks(in cluster: EBMLElement) throws -> [WebMBlock] {
    try children(WebM.ID.simpleBlock, in: cluster).map { block in
      let data = Array(bytes[block.data])
      guard data.count >= 4, data[0] == 0x81 else { throw EBMLReadError(message: "a block not on track 1") }
      return WebMBlock(relativeTime: Int16(bitPattern: UInt16(data[1]) << 8 | UInt16(data[2])), isKeyFrame: data[3] & 0x80 != 0, frame: Array(data[4...]))
    }
  }
}

extension Array where Element == UInt8 {
  fileprivate func containsSubsequence(_ needle: [UInt8]) -> Bool {
    guard !needle.isEmpty, count >= needle.count else { return needle.isEmpty }
    return (0...(count - needle.count)).contains { Array(self[$0..<$0 + needle.count]) == needle }
  }
}

// MARK: - WebMFileReader

final class WebMFileReaderTests: XCTestCase {

  private var fileURL: URL!

  override func setUp() {
    super.setUp()
    fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).webm")
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: fileURL)
    super.tearDown()
  }

  func testReadsTheDurationAndTheFirstKeyFrameDescribedByItsOwnParameterSets() throws {
    let writer = WebMFileWriter(fileURL: fileURL)
    let first = makeH264SampleBuffer(isKeyFrame: true, pts90k: 0)
    try writer.write(first)
    try writer.write(makeH264SampleBuffer(isKeyFrame: false, pts90k: 90000))
    try writer.finish()

    let summary = try WebMFileReader.read(fileURL)
    XCTAssertEqual(summary.duration, 1.033, accuracy: 0.0001)
    let format = try XCTUnwrap(CMSampleBufferGetFormatDescription(summary.firstKeyFrame))
    XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format), kCMVideoCodecType_H264)
    XCTAssertEqual(try format.parameterSets(for: .h264).first, defaultTestSPS)
    let data = try XCTUnwrap(CMSampleBufferGetDataBuffer(summary.firstKeyFrame))
    var bytes = Data()
    try data.appendBytes(to: &bytes)
    XCTAssertEqual([UInt8](bytes), defaultTestAVCCBytes, "the parameter sets are taken out of the picture's data")
  }

  func testAnUnfinishedRecordingReadsToItsLastBlock() throws {
    let writer = WebMFileWriter(fileURL: fileURL)
    try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 0))
    try writer.write(makeH264SampleBuffer(isKeyFrame: false, pts90k: 45000))
    try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 90000))

    XCTAssertEqual(try WebMFileReader.read(fileURL).duration, 0.5, accuracy: 0.0001)
    withExtendedLifetime(writer) {}
  }

  func testReadsHEVC() throws {
    let writer = WebMFileWriter(fileURL: fileURL)
    try writer.write(try XCTUnwrap(makeHEVCSampleBuffer(isKeyFrame: true)))
    try writer.finish()

    let format = try XCTUnwrap(CMSampleBufferGetFormatDescription(try WebMFileReader.read(fileURL).firstKeyFrame))
    XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format), kCMVideoCodecType_HEVC)
  }

  func testReadsAFourByteDuration() throws {
    let writer = WebMFileWriter(fileURL: fileURL)
    try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 0))
    try writer.finish()
    // The eight-byte Duration becomes a four-byte one, padded with a Void to the same size.
    var bytes = [UInt8](try Data(contentsOf: fileURL))
    let duration: [UInt8] = [0x44, 0x89, 0x88]
    let index = try XCTUnwrap((0..<(bytes.count - 2)).first { Array(bytes[$0..<$0 + 3]) == duration })
    let fourBytes = withUnsafeBytes(of: Float(1250).bitPattern.bigEndian) { Array($0) }
    bytes.replaceSubrange(index..<index + 11, with: [0x44, 0x89, 0x84] + fourBytes + [0xEC, 0x82, 0x00, 0x00])
    try Data(bytes).write(to: fileURL)

    XCTAssertEqual(try WebMFileReader.read(fileURL).duration, 1.25, accuracy: 0.0001)
  }

  func testARecordingCutOffAfterAnElementIDReadsUpToIt() throws {
    let writer = WebMFileWriter(fileURL: fileURL)
    try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 0))
    try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 90000))
    let handle = try FileHandle(forWritingTo: fileURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: EBML.id(WebM.ID.cluster))
    try handle.close()

    XCTAssertNoThrow(try WebMFileReader.read(fileURL))
    withExtendedLifetime(writer) {}
  }

  func testALacedBlockIsRefusedRatherThanMisread() throws {
    let writer = WebMFileWriter(fileURL: fileURL)
    try writer.write(makeH264SampleBuffer(isKeyFrame: true, pts90k: 0))
    try writer.finish()
    // A SimpleBlock on track 1 at time 0 with the keyframe flag, then with Xiph lacing set as well.
    var bytes = [UInt8](try Data(contentsOf: fileURL))
    let header: [UInt8] = [0x81, 0x00, 0x00, 0x80]
    let index = try XCTUnwrap((0..<(bytes.count - 3)).first { Array(bytes[$0..<$0 + 4]) == header })
    bytes[index + 3] = 0x82
    try Data(bytes).write(to: fileURL)

    XCTAssertThrowsError(try WebMFileReader.read(fileURL))
  }

  func testAFileThatIsNotWebMIsRefused() throws {
    try Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]).write(to: fileURL)
    XCTAssertThrowsError(try WebMFileReader.read(fileURL))
  }
}
