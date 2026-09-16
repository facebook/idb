/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import Foundation

extension VideoStreamCodec {
  var fmp4CompatibleBrand: String {
    switch self {
    case .h264:
      return "mp41"
    case .hevc:
      return "hvc1"
    }
  }

  var fmp4SampleEntryType: String {
    switch self {
    case .h264:
      return "avc1"
    case .hevc:
      return "hvc1"
    }
  }

  var fmp4CodecConfigType: String {
    switch self {
    case .h264:
      return "avcC"
    case .hevc:
      return "hvcC"
    }
  }
}

private struct FMP4BoxWriter {
  private(set) var data: [UInt8]

  init(capacity: Int = 0) {
    data = []
    data.reserveCapacity(capacity)
  }

  var count: Int {
    data.count
  }

  mutating func write8(_ value: UInt8) {
    data.append(value)
  }

  mutating func write16(_ value: UInt16) {
    let be = value.bigEndian
    withUnsafeBytes(of: be) { data.append(contentsOf: $0) }
  }

  mutating func write32(_ value: UInt32) {
    let be = value.bigEndian
    withUnsafeBytes(of: be) { data.append(contentsOf: $0) }
  }

  mutating func write64(_ value: UInt64) {
    let be = value.bigEndian
    withUnsafeBytes(of: be) { data.append(contentsOf: $0) }
  }

  mutating func writeBox(_ type: String, contents: (inout Self) -> Void) {
    let sizeOffset = data.count
    write32(0)
    writeBytes(type)
    contents(&self)
    write32(UInt32(data.count - sizeOffset), at: sizeOffset)
  }

  mutating func writeFullBoxHeader(version: UInt8, flags: UInt32) {
    write32((UInt32(version) << 24) | (flags & 0x00FFFFFF))
  }

  mutating func writeZeros(_ count: Int) {
    assert(count <= 64, "Zero count greater than 64")
    data.append(contentsOf: [UInt8](repeating: 0, count: count))
  }

  mutating func writeBytes(_ string: String) {
    data.append(contentsOf: string.utf8)
  }

  mutating func append(_ bytes: [UInt8]) {
    data.append(contentsOf: bytes)
  }

  mutating func append(_ data: Data) {
    self.data.append(contentsOf: data)
  }

  mutating func append(_ bytes: UnsafeBufferPointer<UInt8>) {
    data.append(contentsOf: bytes)
  }

  mutating func write32(_ value: UInt32, at offset: Int) {
    let be = value.bigEndian
    withUnsafeBytes(of: be) { bytes in
      for k in 0..<4 {
        data[offset + k] = bytes[k]
      }
    }
  }
}

private func FBFMP4GetCodecConfigAtom(_ formatDescription: CMFormatDescription, _ codec: VideoStreamCodec) -> [UInt8]? {
  if let atoms = CMFormatDescriptionGetExtension(formatDescription, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any] {
    if let configData = atoms[codec.fmp4CodecConfigType] as? Data {
      return [UInt8](configData)
    }
  }
  // Fallback: build avcC/hvcC manually from parameter sets.
  var writer = FMP4BoxWriter()
  switch codec {
  case .h264:
    var sps: UnsafePointer<UInt8>?
    var spsSize = 0
    var paramCount = 0
    let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 0, parameterSetPointerOut: &sps, parameterSetSizeOut: &spsSize, parameterSetCountOut: &paramCount, nalUnitHeaderLengthOut: nil)
    guard status == noErr, spsSize >= 4, let sps else {
      return nil
    }

    var pps: UnsafePointer<UInt8>?
    var ppsSize = 0
    if paramCount > 1 {
      CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 1, parameterSetPointerOut: &pps, parameterSetSizeOut: &ppsSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
    }

    writer.write8(1)
    writer.write8(sps[1])
    writer.write8(sps[2])
    writer.write8(sps[3])
    writer.write8(0xFF)
    writer.write8(0xE1)
    writer.write16(UInt16(spsSize))
    writer.append(UnsafeBufferPointer(start: sps, count: spsSize))
    writer.write8(pps != nil ? 1 : 0)
    if let pps {
      writer.write16(UInt16(ppsSize))
      writer.append(UnsafeBufferPointer(start: pps, count: ppsSize))
    }
  case .hevc:
    var paramCount = 0
    let status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(formatDescription, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &paramCount, nalUnitHeaderLengthOut: nil)
    if status != noErr {
      return nil
    }

    var paramSets = [[UInt8]]()
    var paramTypes = [UInt8]()
    for i in 0..<paramCount {
      var ps: UnsafePointer<UInt8>?
      var psSize = 0
      CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(formatDescription, parameterSetIndex: i, parameterSetPointerOut: &ps, parameterSetSizeOut: &psSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
      if let ps, psSize > 0 {
        paramSets.append([UInt8](UnsafeBufferPointer(start: ps, count: psSize)))
        let nalType = (ps[0] >> 1) & 0x3F
        paramTypes.append(nalType)
      }
    }

    writer.write8(1)
    writer.write8(0)
    writer.write32(0)
    writer.write16(0)
    writer.write32(0)
    writer.write8(0)
    writer.write16(0xF000)
    writer.write8(0xFC)
    writer.write8(0xFC)
    writer.write8(0xF8)
    writer.write8(0xF8)
    writer.write16(0)
    writer.write8(0x0F)

    // Group parameter sets by NAL type, in first-seen order.
    var groupedOrder = [UInt8]()
    var grouped = [UInt8: [[UInt8]]]()
    for i in 0..<paramSets.count {
      let type = paramTypes[i]
      if grouped[type] == nil {
        grouped[type] = []
        groupedOrder.append(type)
      }
      grouped[type]?.append(paramSets[i])
    }

    writer.write8(UInt8(groupedOrder.count))
    for nalType in groupedOrder {
      let sets = grouped[nalType] ?? []
      writer.write8(nalType & 0x3F)
      writer.write16(UInt16(sets.count))
      for set in sets {
        writer.write16(UInt16(set.count))
        writer.append(set)
      }
    }
  }
  return writer.data
}

private func FBFMP4CreateFtypBox(_ codec: VideoStreamCodec) -> [UInt8] {
  var writer = FMP4BoxWriter(capacity: 24)
  writer.writeBox("ftyp") { writer in
    writer.writeBytes("isom")
    writer.write32(0x200)
    writer.writeBytes("isom")
    writer.writeBytes("iso6")
    writer.writeBytes(codec.fmp4CompatibleBrand)
  }
  return writer.data
}

private func FBFMP4CreateMoovBox(_ formatDescription: CMFormatDescription, _ codec: VideoStreamCodec, _ width: UInt32, _ height: UInt32, _ timescale: UInt32) -> [UInt8] {
  var writer = FMP4BoxWriter(capacity: 512)

  let codecConfig = FBFMP4GetCodecConfigAtom(formatDescription, codec)

  writer.writeBox("moov") { writer in
    writer.writeBox("mvhd") { writer in
      writer.writeFullBoxHeader(version: 0, flags: 0)
      writer.write32(0)
      writer.write32(0)
      writer.write32(timescale)
      writer.write32(0)
      writer.write32(0x00010000)
      writer.write16(0x0100)
      writer.writeZeros(10)
      let matrix: [UInt32] = [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000]
      for i in 0..<9 {
        writer.write32(matrix[i])
      }
      writer.writeZeros(24)
      writer.write32(2)
    }

    writer.writeBox("trak") { writer in
      writer.writeBox("tkhd") { writer in
        writer.writeFullBoxHeader(version: 0, flags: 0x03)
        writer.write32(0)
        writer.write32(0)
        writer.write32(1)
        writer.write32(0)
        writer.write32(0)
        writer.writeZeros(8)
        writer.write16(0)
        writer.write16(0)
        writer.write16(0)
        writer.write16(0)
        let matrix: [UInt32] = [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000]
        for i in 0..<9 {
          writer.write32(matrix[i])
        }
        writer.write32(width << 16)
        writer.write32(height << 16)
      }

      writer.writeBox("mdia") { writer in
        writer.writeBox("mdhd") { writer in
          writer.writeFullBoxHeader(version: 0, flags: 0)
          writer.write32(0)
          writer.write32(0)
          writer.write32(timescale)
          writer.write32(0)
          writer.write16(0x55C4)
          writer.write16(0)
        }

        writer.writeBox("hdlr") { writer in
          writer.writeFullBoxHeader(version: 0, flags: 0)
          writer.write32(0)
          writer.writeBytes("vide")
          writer.writeZeros(12)
          writer.writeBytes("VideoHandler")
          writer.write8(0)
        }

        writer.writeBox("minf") { writer in
          writer.writeBox("vmhd") { writer in
            writer.writeFullBoxHeader(version: 0, flags: 1)
            writer.write16(0)
            writer.writeZeros(6)
          }

          writer.writeBox("dinf") { writer in
            writer.writeBox("dref") { writer in
              writer.writeFullBoxHeader(version: 0, flags: 0)
              writer.write32(1)
              writer.writeBox("url ") { writer in
                writer.writeFullBoxHeader(version: 0, flags: 1)
              }
            }
          }

          writer.writeBox("stbl") { writer in
            writer.writeBox("stsd") { writer in
              writer.writeFullBoxHeader(version: 0, flags: 0)
              writer.write32(1)

              writer.writeBox(codec.fmp4SampleEntryType) { writer in
                writer.writeZeros(6)
                writer.write16(1)
                writer.writeZeros(16)
                writer.write16(UInt16(width))
                writer.write16(UInt16(height))
                writer.write32(0x00480000)
                writer.write32(0x00480000)
                writer.write32(0)
                writer.write16(1)
                writer.writeZeros(32)
                writer.write16(0x0018)
                writer.write16(0xFFFF)

                if let codecConfig {
                  writer.writeBox(codec.fmp4CodecConfigType) { writer in
                    writer.append(codecConfig)
                  }
                }
              }
            }

            writer.writeBox("stts") { writer in
              writer.writeFullBoxHeader(version: 0, flags: 0)
              writer.write32(0)
            }
            writer.writeBox("stsc") { writer in
              writer.writeFullBoxHeader(version: 0, flags: 0)
              writer.write32(0)
            }
            writer.writeBox("stsz") { writer in
              writer.writeFullBoxHeader(version: 0, flags: 0)
              writer.write32(0)
              writer.write32(0)
            }
            writer.writeBox("stco") { writer in
              writer.writeFullBoxHeader(version: 0, flags: 0)
              writer.write32(0)
            }
          }
        }
      }
    }

    writer.writeBox("mvex") { writer in
      writer.writeBox("trex") { writer in
        writer.writeFullBoxHeader(version: 0, flags: 0)
        writer.write32(1)
        writer.write32(1)
        writer.write32(0)
        writer.write32(0)
        writer.write32(0)
      }
    }
  }
  return writer.data
}

// moof + mdat header for a single-sample fragment. The sample data is not included: the caller
// must append exactly `sampleSize` bytes after the returned bytes.
private func FBFMP4CreateFragmentHeader(_ sequenceNumber: UInt32, _ baseDecodeTime: UInt64, _ duration: UInt32, _ sampleSize: UInt32, _ isKeyFrame: Bool) -> [UInt8] {
  let trunFlags: UInt32 = 0x000701
  // trun: header(12) + data_offset(4) + 1 sample entry (duration(4) + size(4) + flags(4))
  let trunSize = 12 + 4 + 12
  let moofSize = 8 + 16 + 8 + 16 + 20 + trunSize
  let mdatHeaderSize = 8

  var writer = FMP4BoxWriter(capacity: moofSize + mdatHeaderSize)

  let moofOffset = writer.count
  writer.writeBox("moof") { writer in
    writer.writeBox("mfhd") { writer in
      writer.writeFullBoxHeader(version: 0, flags: 0)
      writer.write32(sequenceNumber)
    }

    writer.writeBox("traf") { writer in
      writer.writeBox("tfhd") { writer in
        writer.writeFullBoxHeader(version: 0, flags: 0x020000)
        writer.write32(1)
      }

      writer.writeBox("tfdt") { writer in
        writer.writeFullBoxHeader(version: 1, flags: 0)
        writer.write64(baseDecodeTime)
      }

      writer.writeBox("trun") { writer in
        writer.writeFullBoxHeader(version: 0, flags: trunFlags)
        writer.write32(1) // sample_count = 1
        writer.write32(0) // placeholder for data_offset (patched below)
        writer.write32(duration)
        writer.write32(sampleSize)
        writer.write32(isKeyFrame ? 0x02000000 : 0x01010000)
      }
    }
  }

  // Patch data_offset: distance from moof start to first sample byte in mdat.
  let actualMoofSize = UInt32(writer.count - moofOffset)
  let dataOffset = actualMoofSize + UInt32(mdatHeaderSize)
  // patchPos = moofOffset + moof_header(8) + mfhd(16) + traf_header(8) + tfhd(16) + tfdt(20) + trun_header(12) + sample_count(4)
  let patchPos = moofOffset + 8 + 16 + 8 + 16 + 20 + 12 + 4
  writer.write32(dataOffset, at: patchPos)

  // mdat header only — caller appends sample data.
  writer.write32(UInt32(mdatHeaderSize) + sampleSize)
  writer.writeBytes("mdat")

  return writer.data
}

final class FMP4FrameWriter: EncodedFrameWriter, VideoStreamTimedMetadataWriter {
  private let codec: VideoStreamCodec
  private(set) var initWritten: Bool
  private(set) var sequenceNumber: UInt32
  private var baseDecodeTime: UInt64
  private var firstPts90k: UInt64
  var lastPts90k: UInt64
  /// The format description the current init segment describes. A keyframe carrying a different
  /// one (a rotation changes the SPS) gets a fresh init segment ahead of it, so that the
  /// `avcC`/`hvcC` record decoders configure themselves from matches the samples that follow. The
  /// timeline continues across the re-initialisation.
  private var initFormatDescription: CMFormatDescription?

  public init(codec: VideoStreamCodec) {
    self.codec = codec
    self.initWritten = false
    self.sequenceNumber = 0
    self.baseDecodeTime = 0
    self.firstPts90k = 0
    self.lastPts90k = 0
  }

  public func write(_ sampleBuffer: CMSampleBuffer, to consumer: any DataConsumer, logger: any ControlCoreLogger) throws {
    if !CMSampleBufferDataIsReady(sampleBuffer) {
      throw VideoStreamWriterError.sampleBufferNotReady
    }

    let isKeyFrame = FBVideoSampleBufferIsKeyFrame(sampleBuffer)

    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    let pts90k = UInt64(CMTimeGetSeconds(pts) * 90000.0)
    let prevPts90k = lastPts90k
    lastPts90k = pts90k

    // One write per frame: an async consumer counts writes against its drop threshold, so the init
    // segment, the fragment header and the sample data are assembled into a single item.
    var output = Data()

    if !initWritten, !isKeyFrame {
      return // Drop frames before first keyframe.
    }

    // An init segment (ftyp + moov) ahead of the first keyframe, and again ahead of a keyframe whose
    // format differs from the one the last init segment described.
    if isKeyFrame {
      guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else {
        throw VideoStreamWriterError.failedToGetFormatDescription
      }
      let formatChanged = initFormatDescription.map { !CMFormatDescriptionEqual($0, otherFormatDescription: formatDesc) } ?? true
      if formatChanged {
        let dims = CMVideoFormatDescriptionGetDimensions(formatDesc)
        output.append(contentsOf: FBFMP4CreateFtypBox(codec))
        output.append(contentsOf: FBFMP4CreateMoovBox(formatDesc, codec, UInt32(dims.width), UInt32(dims.height), 90000))
        if !initWritten {
          initWritten = true
          firstPts90k = pts90k
          baseDecodeTime = 0
        }
        initFormatDescription = formatDesc
        logger.log("fMP4 init segment written (\(dims.width)x\(dims.height), \(codec.displayName))")
      }
    }

    let duration90k: UInt32
    let sampleDuration = CMSampleBufferGetDuration(sampleBuffer)
    if CMTIME_IS_VALID(sampleDuration) && CMTimeGetSeconds(sampleDuration) > 0 {
      duration90k = UInt32(CMTimeGetSeconds(sampleDuration) * 90000.0)
    } else if prevPts90k > 0 && pts90k > prevPts90k {
      duration90k = UInt32(pts90k - prevPts90k)
    } else {
      duration90k = 3000 // ~33ms at 30fps fallback
    }

    // The fragment's decode time is the sample's own presentation time, relative to the first
    // sample — never the running sum of declared durations, which drifts from real time whenever
    // a source misses its nominal cadence.
    if pts90k >= firstPts90k {
      baseDecodeTime = pts90k - firstPts90k
    }

    // Get AVCC NAL data (do NOT convert to Annex-B).
    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
      throw VideoStreamWriterError.failedToGetDataBuffer
    }
    let dataLength = CMBlockBufferGetDataLength(dataBuffer)

    // moof + mdat header, then the sample data.
    sequenceNumber += 1
    output.append(contentsOf: FBFMP4CreateFragmentHeader(sequenceNumber, baseDecodeTime, duration90k, UInt32(dataLength), isKeyFrame))
    try AppendBlockBuffer(dataBuffer, length: dataLength, to: &output)
    consumer.consumeData(output)

  }

  public func writeTimedMetadata(_ text: String, to consumer: any DataConsumer) {
    consumer.consumeData(FBFMP4CreateEmsgBox(lastPts90k, text))
  }
}

private func FBFMP4CreateEmsgBox(_ presentationTime90k: UInt64, _ text: String) -> Data {
  let textData = [UInt8](text.utf8)

  var writer = FMP4BoxWriter(capacity: 64 + textData.count)

  writer.writeBox("emsg") { writer in
    writer.writeFullBoxHeader(version: 1, flags: 0)
    writer.write32(90000)
    writer.write64(presentationTime90k)
    writer.write32(0)
    writer.write32(0)

    let scheme = "urn:sime2e:chapter"
    writer.writeBytes(scheme)
    writer.write8(0) // null terminator
    writer.write8(0) // empty value string
    writer.append(textData)
  }

  return Data(writer.data)
}
