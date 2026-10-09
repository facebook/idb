/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreAudio
import Foundation
@_implementationOnly import ShimulatorAudioInjectionHAL
@_implementationOnly import ShimulatorAudioInjectionPrivate
import Synchronization
import XCTest

private func fourCC(_ code: String) -> UInt32 {
  code.utf8.reduce(0) { $0 << 8 | UInt32($1) }
}

private struct Recorded {
  var proc: IDBAudioDeviceIOProc?
  var clientData: UInt = 0
  var createdHandle: UInt = 0x1234
  var createStatus: OSStatus = noErr
  var destroyStatus: OSStatus = noErr
  var originalCallbacks = 0
  var destroyCount = 0
  var controllerStarts = 0
  var propertyRate: Double = 44_100
  var inputStreamBytes: UInt32 = 0
  var defaultInputDevice: IDBAudioObjectID = 0
  var capturedInput: [Float] = []
  var capturedInputBytes: UInt32 = 0
  var hasPropertyAnswer = true
  var defaultInputStatus: OSStatus = noErr
  var calls: [String] = []
}

private let recorded = Mutex(Recorded())
private let defaultOutputDevice: IDBAudioObjectID = 73

private func withFake<Result: Sendable>(_ body: (inout Recorded) -> Result) -> Result {
  recorded.withLock { body(&$0) }
}

private let hal = AudioHAL(
  armed: true,
  createIOProcID: { _, proc, clientData, handle in
    withFake {
      $0.calls.append("create")
      $0.proc = proc
      $0.clientData = UInt(bitPattern: clientData)
      if $0.createStatus == noErr {
        handle?.pointee = UnsafeMutableRawPointer(bitPattern: $0.createdHandle)
      }
      return $0.createStatus
    }
  },
  destroyIOProcID: { _, _ in
    withFake {
      $0.calls.append("destroy")
      $0.destroyCount += 1
      return $0.destroyStatus
    }
  },
  getPropertyData: { _, address, _, _, size, data in
    withFake {
      $0.calls.append("get")
      switch address?.pointee.selector ?? 0 {
      case fourCC("dOut"):
        data?.storeBytes(of: defaultOutputDevice, as: IDBAudioObjectID.self)
      case fourCC("dIn "):
        guard $0.defaultInputStatus == noErr else { return $0.defaultInputStatus }
        data?.storeBytes(of: $0.defaultInputDevice, as: IDBAudioObjectID.self)
      default:
        if let size, size.pointee >= MemoryLayout<Double>.size {
          data?.storeBytes(of: $0.propertyRate, as: Double.self)
        }
      }
      return noErr
    }
  },
  getPropertyDataSize: { _, _, _, _, size in
    size?.pointee = withFake {
      $0.calls.append("size")
      return $0.inputStreamBytes
    }
    return noErr
  },
  hasProperty: { _, _ in
    withFake {
      $0.calls.append("has")
      return $0.hasPropertyAnswer
    }
  },
  addPropertyListener: { _, _, _, _ in
    withFake { $0.calls.append("listen") }
    return 31
  },
  addPropertyListenerBlock: { _, _, _, _ in
    withFake { $0.calls.append("listenBlock") }
    return 32
  },
  startController: { withFake { $0.controllerStarts += 1 } })

private let originalProc: IDBAudioDeviceIOProc = { _, _, _, _, _, _, _ in
  withFake { $0.originalCallbacks += 1 }
  return 17
}

private let capturingProc: IDBAudioDeviceIOProc = { _, _, input, _, _, _, _ in
  guard let buffer = input?.pointee.mBuffers, let data = buffer.mData else {
    return -1
  }
  let samples = data.assumingMemoryBound(to: Float.self)
  let captured = (0..<min(2, Int(buffer.mDataByteSize) / 4)).map { samples[$0] }
  withFake {
    $0.capturedInput = captured
    $0.capturedInputBytes = buffer.mDataByteSize
  }
  return 17
}

final class AudioInjectionHALTests: XCTestCase {
  private let engine = HALAudioInjectionEngine()

  override func setUp() {
    super.setUp()
    withFake { $0 = Recorded() }
    engine.clear()
  }

  private func create(
    _ device: IDBAudioObjectID, _ proc: IDBAudioDeviceIOProc = originalProc
  )
    -> (OSStatus, UnsafeMutableRawPointer?)
  {
    var handle: UnsafeMutableRawPointer?
    let status = AudioInjectionHAL.createIOProcID(
      hal, device: device, proc: proc, clientData: nil, outIOProcID: &handle)
    return (status, handle)
  }

  private func destroy(_ device: IDBAudioObjectID, _ handle: UnsafeMutableRawPointer?) -> OSStatus {
    AudioInjectionHAL.destroyIOProcID(hal, device: device, ioProcID: handle)
  }

  private func invoke(
    _ device: IDBAudioObjectID, _ input: UnsafePointer<AudioBufferList>? = nil,
    output: UnsafeMutablePointer<AudioBufferList>? = nil
  ) -> OSStatus {
    let (proc, clientData) = withFake { ($0.proc, $0.clientData) }
    return proc?(device, nil, input, nil, output, nil, UnsafeMutableRawPointer(bitPattern: clientData)) ?? -1
  }

  private func callback(
    _ device: IDBAudioObjectID, input: inout [Float], channels: UInt32 = 1
  ) -> OSStatus {
    input.withUnsafeMutableBytes { bytes in
      var list = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(mNumberChannels: channels, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
      return invoke(device, &list)
    }
  }

  private func address(_ selector: String, _ scope: String = "glob") -> IDBAudioObjectPropertyAddress {
    IDBAudioObjectPropertyAddress(selector: fourCC(selector), scope: fourCC(scope), element: 0)
  }

  private func property<Value>(
    _ object: IDBAudioObjectID, _ address: IDBAudioObjectPropertyAddress, _ value: inout Value
  )
    -> Bool
  {
    var address = address
    var size = UInt32(MemoryLayout<Value>.size)
    return withUnsafeMutableBytes(of: &value) {
      AudioInjectionHAL.syntheticProperty(hal, object: object, address: &address, dataSize: &size, data: $0.baseAddress)
    }
  }

  func testInjectedSamplesReachTheOriginalCallback() throws {
    let (_, handle) = create(8)
    engine.replace(samples: [.max, .min], sampleRate: 48_000, generation: 1)
    _ = engine.pollProgress()
    var output: [Float] = [0, 0]

    XCTAssertEqual(callback(8, input: &output), 17)
    XCTAssertEqual(output[0], 1, accuracy: 0.0001)
    XCTAssertEqual(output[1], -1, accuracy: 0.0001)
    XCTAssertEqual(withFake { $0.originalCallbacks }, 1)
    XCTAssertEqual(destroy(8, handle), noErr)
  }

  func testUnknownRateDefersInjectionUntilPollingPreparesIt() {
    let (_, handle) = create(8)
    let samples = (1...48).map { Int16($0 * 100) }
    engine.replace(samples: samples, sampleRate: 48_000, generation: 1)
    var input = Array(repeating: Float(0.25), count: 48)

    XCTAssertEqual(callback(8, input: &input), 17)
    XCTAssertEqual(input, Array(repeating: Float(0.25), count: 48))
    XCTAssertEqual(engine.pollProgress(), .init(generation: 1, started: false, finished: false))

    XCTAssertEqual(callback(8, input: &input), 17)
    for frame in input.indices {
      let index = Int(Double(frame) * 48_000 / 44_100)
      let expected = index < samples.count ? Float(samples[index]) / Float(Int16.max) : 0
      XCTAssertEqual(input[frame], expected, accuracy: 0.0001)
    }
    XCTAssertEqual(engine.pollProgress(), .init(generation: 1, started: true, finished: true))
    XCTAssertEqual(withFake { $0.originalCallbacks }, 2)
    XCTAssertEqual(destroy(8, handle), noErr)
  }

  func testPendingRateKeepsTheClipAvailableForAnotherInputProc() {
    let (_, firstHandle) = create(8)
    let samples = (1...48).map { Int16($0 * 100) }
    engine.replace(samples: samples, sampleRate: 48_000, generation: 1)
    _ = engine.pollProgress()
    var first = Array(repeating: Float(0.25), count: 48)
    XCTAssertEqual(callback(8, input: &first), 17)

    let (_, secondHandle) = create(9)
    var second = Array(repeating: Float(0.25), count: 48)
    XCTAssertEqual(callback(9, input: &second), 17)
    XCTAssertEqual(second, Array(repeating: Float(0.25), count: 48))
    XCTAssertEqual(engine.pollProgress(), .init(generation: 1, started: true, finished: false))

    XCTAssertEqual(callback(9, input: &second), 17)
    for frame in second.indices {
      let index = Int(Double(frame) * 48_000 / 44_100)
      let expected = index < samples.count ? Float(samples[index]) / Float(Int16.max) : 0
      XCTAssertEqual(second[frame], expected, accuracy: 0.0001)
    }
    XCTAssertEqual(engine.pollProgress(), .init(generation: 1, started: true, finished: true))
    XCTAssertEqual(destroy(8, firstHandle), noErr)
    XCTAssertEqual(destroy(9, secondHandle), noErr)
  }

  func testResamplingContinuesAcrossCallbacks() throws {
    let (_, handle) = create(9)
    withFake { $0.propertyRate = 96_000 }
    engine.replace(samples: [.max, 0, .min + 1], sampleRate: 48_000, generation: 1)
    _ = engine.pollProgress()
    var first: [Float] = [9, 9, 9]
    var second: [Float] = [9, 9, 9]

    _ = callback(9, input: &first)
    _ = callback(9, input: &second)

    for (actual, expected) in zip(first + second, [1, 1, 0, 0, -1, -1] as [Float]) {
      XCTAssertEqual(actual, expected, accuracy: 0.0001)
    }
    XCTAssertEqual(destroy(9, handle), noErr)
  }

  func testControllerStartsOnlyAfterAnInputCallback() {
    let (_, handle) = create(7)
    XCTAssertEqual(withFake { $0.controllerStarts }, 0)

    XCTAssertEqual(invoke(7), 17)
    XCTAssertEqual(withFake { $0.controllerStarts }, 0)

    var input: [Float] = [0]
    XCTAssertEqual(callback(7, input: &input), 17)
    XCTAssertEqual(withFake { $0.controllerStarts }, 1)
    XCTAssertEqual(destroy(7, handle), noErr)
  }

  func testZeroCapacityBufferIsNotWritten() throws {
    let (_, handle) = create(8)
    engine.replace(samples: [.max, .min], sampleRate: 48_000, generation: 1)
    _ = engine.pollProgress()
    var output: [Float] = [0, 0]
    var canary: Float = 42
    let storage = UnsafeMutableRawPointer.allocate(
      byteCount: MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.stride,
      alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { storage.deallocate() }
    let list = UnsafeMutableAudioBufferListPointer(storage.bindMemory(to: AudioBufferList.self, capacity: 1))
    list.count = 2

    output.withUnsafeMutableBytes { bytes in
      withUnsafeMutablePointer(to: &canary) { canary in
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress)
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 1, mData: canary)
        XCTAssertEqual(invoke(8, list.unsafePointer), 17)
      }
    }

    XCTAssertEqual(output[0], 1, accuracy: 0.0001)
    XCTAssertEqual(output[1], -1, accuracy: 0.0001)
    XCTAssertEqual(canary, 42)
    XCTAssertEqual(destroy(8, handle), noErr)
  }

  func testFailedDestroyKeepsForwardingCallbacks() {
    let (_, handle) = create(9)
    withFake { $0.destroyStatus = -7 }

    XCTAssertEqual(destroy(9, handle), -7)
    XCTAssertEqual(invoke(9), 17)
    XCTAssertEqual(withFake { $0.originalCallbacks }, 1)

    withFake { $0.destroyStatus = noErr }
    XCTAssertEqual(destroy(9, handle), noErr)
  }

  func testCallbackRacingADestroyNeverReachesTheApp() {
    let (_, handle) = create(9)
    XCTAssertEqual(destroy(9, handle), noErr)

    var input: [Float] = [0]
    XCTAssertEqual(callback(9, input: &input), noErr)
    XCTAssertEqual(withFake { $0.originalCallbacks }, 0)
  }

  func testFinishedStaysReportedUntilTheNextInjection() throws {
    let (_, handle) = create(8)
    engine.replace(samples: [.max, .min], sampleRate: 48_000, generation: 1)
    _ = engine.pollProgress()
    var output: [Float] = [0, 0]
    _ = callback(8, input: &output)

    for _ in 0..<2 {
      XCTAssertEqual(engine.pollProgress(), .init(generation: 1, started: true, finished: true))
    }

    engine.replace(samples: [.max, .min], sampleRate: 48_000, generation: 2)
    XCTAssertEqual(engine.pollProgress(), .init(generation: 2, started: false, finished: false))
    XCTAssertEqual(destroy(8, handle), noErr)
  }

  func testCreateFailureIsReturnedWithoutAHandle() {
    withFake { $0.createStatus = -7 }

    let (status, handle) = create(11)

    XCTAssertEqual(status, -7)
    XCTAssertNil(handle)
  }

  func testSuccessfulCreateWithoutAHandleIsAnError() {
    withFake { $0.createdHandle = 0 }

    let (status, handle) = create(11)

    XCTAssertEqual(status, -50)
    XCTAssertNil(handle)
  }

  func testDeviceWithoutInputOffersTheSyntheticStream() {
    var device: IDBAudioObjectID = 0
    XCTAssertTrue(property(1, address("dIn "), &device))
    XCTAssertEqual(device, defaultOutputDevice)

    var stream: IDBAudioObjectID = 0
    XCTAssertTrue(property(defaultOutputDevice, address("stm#", "inpt"), &stream))
    XCTAssertTrue(AudioInjectionHAL.isSyntheticStream(stream))

    var format = AudioStreamBasicDescription()
    XCTAssertTrue(property(stream, address("sfmt"), &format))
    XCTAssertEqual(format.mSampleRate, withFake { $0.propertyRate })
    XCTAssertEqual(format.mFormatID, kAudioFormatLinearPCM)
    XCTAssertEqual(format.mChannelsPerFrame, 1)
    XCTAssertEqual(format.mBitsPerChannel, 32)

    withFake { $0.inputStreamBytes = UInt32(MemoryLayout<IDBAudioObjectID>.size) }
    XCTAssertFalse(property(defaultOutputDevice, address("stm#", "inpt"), &stream))
  }

  func testDeviceWithoutInputReceivesInjectedSamples() throws {
    var stream: IDBAudioObjectID = 0
    XCTAssertTrue(property(104, address("stm#", "inpt"), &stream))
    var latency: UInt32 = 1
    XCTAssertTrue(property(stream, address("ltnc"), &latency))
    let (status, handle) = create(104, capturingProc)
    XCTAssertEqual(status, noErr)
    engine.replace(samples: [.max, .min], sampleRate: 44_100, generation: 1)
    _ = engine.pollProgress()
    var output: [Float] = [0, 0, 0, 0]

    let result = output.withUnsafeMutableBytes { bytes in
      var list = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
      return invoke(104, output: &list)
    }

    XCTAssertEqual(result, 17)
    XCTAssertEqual(withFake { $0.capturedInput }[0], 1, accuracy: 0.0001)
    XCTAssertEqual(withFake { $0.capturedInput }[1], -1, accuracy: 0.0001)
    XCTAssertEqual(withFake { $0.capturedInputBytes }, 2 * 4)
    XCTAssertEqual(withFake { $0.controllerStarts }, 1)
    XCTAssertEqual(destroy(104, handle), noErr)
  }

  func testPlaybackOnlyDeviceWithoutInputIsNotFilled() throws {
    let (_, handle) = create(105, capturingProc)
    engine.replace(samples: [.max, .min], sampleRate: 44_100, generation: 1)
    _ = engine.pollProgress()

    XCTAssertEqual(invoke(105), 17)
    XCTAssertEqual(withFake { $0.capturedInput }.first, 0)
    XCTAssertEqual(withFake { $0.controllerStarts }, 0)
    XCTAssertFalse(engine.pollProgress().started)
    XCTAssertEqual(destroy(105, handle), noErr)
  }

  func testHostWithAMicrophoneIsLeftAlone() {
    withFake { $0.defaultInputDevice = 80 }
    var answer: IDBAudioObjectID = 0

    XCTAssertFalse(property(1, address("dIn "), &answer))
    XCTAssertFalse(property(defaultOutputDevice, address("stm#", "inpt"), &answer))
  }

  func testFailedDefaultInputReadIsLeftAlone() {
    withFake { $0.defaultInputStatus = -7 }
    var answer: IDBAudioObjectID = 0

    XCTAssertFalse(property(1, address("dIn "), &answer))
    XCTAssertFalse(property(defaultOutputDevice, address("stm#", "inpt"), &answer))
  }

  func testLatencyProbeWithoutReadingItDoesNotMakeARecorder() throws {
    var stream: IDBAudioObjectID = 0
    XCTAssertTrue(property(106, address("stm#", "inpt"), &stream))
    var latency = address("ltnc")
    var size: UInt32 = 0
    XCTAssertEqual(
      AudioInjectionHAL.getPropertyDataSize(
        hal, object: stream, address: &latency, qualifierDataSize: 0, qualifierData: nil, dataSize: &size),
      noErr)
    XCTAssertTrue(AudioInjectionHAL.hasProperty(hal, object: stream, address: &latency))
    let (_, handle) = create(106, capturingProc)
    engine.replace(samples: [.max, .min], sampleRate: 44_100, generation: 1)
    _ = engine.pollProgress()

    XCTAssertEqual(invoke(106), 17)
    XCTAssertEqual(withFake { $0.capturedInput }.first, 0)
    XCTAssertEqual(withFake { $0.controllerStarts }, 0)
    XCTAssertEqual(destroy(106, handle), noErr)
  }

  func testRecordersThatAllReadLatencyBeforeCreatingAreAllFilled() throws {
    var stream: IDBAudioObjectID = 0
    XCTAssertTrue(property(109, address("stm#", "inpt"), &stream))
    var latency: UInt32 = 1
    for _ in 0..<9 {
      XCTAssertTrue(property(stream, address("ltnc"), &latency))
    }
    var handles: [UnsafeMutableRawPointer?] = []
    for _ in 0..<9 {
      handles.append(create(109, capturingProc).1)
    }
    engine.replace(samples: [.max, .min], sampleRate: 44_100, generation: 1)
    _ = engine.pollProgress()

    XCTAssertEqual(invoke(109), 17)
    XCTAssertEqual(withFake { $0.capturedInput }.first ?? 0, 1, accuracy: 0.0001)
    for handle in handles {
      XCTAssertEqual(destroy(109, handle), noErr)
    }
  }

  func testARecorderIndicationEndsWithTheRecorder() throws {
    var stream: IDBAudioObjectID = 0
    XCTAssertTrue(property(107, address("stm#", "inpt"), &stream))
    var latency: UInt32 = 1
    XCTAssertTrue(property(stream, address("ltnc"), &latency))
    let (_, recorder) = create(107, capturingProc)
    XCTAssertEqual(destroy(107, recorder), noErr)

    let (_, player) = create(107, capturingProc)
    engine.replace(samples: [.max, .min], sampleRate: 44_100, generation: 1)
    _ = engine.pollProgress()

    XCTAssertEqual(invoke(107), 17)
    XCTAssertEqual(withFake { $0.capturedInput }.first, 0)
    XCTAssertFalse(engine.pollProgress().started)
    XCTAssertEqual(destroy(107, player), noErr)
  }

  func testARecorderThatReadsLatencyAfterCreatingItsIOProcIsFilled() throws {
    var stream: IDBAudioObjectID = 0
    XCTAssertTrue(property(108, address("stm#", "inpt"), &stream))
    let (_, handle) = create(108, capturingProc)
    var latency: UInt32 = 1
    XCTAssertTrue(property(stream, address("ltnc"), &latency))
    engine.replace(samples: [.max, .min], sampleRate: 44_100, generation: 1)
    _ = engine.pollProgress()

    XCTAssertEqual(invoke(108), 17)
    XCTAssertEqual(withFake { $0.capturedInput }.first ?? 0, 1, accuracy: 0.0001)
    XCTAssertEqual(destroy(108, handle), noErr)
  }

  func testSyntheticStreamAnswersOnlyItsOwnProperties() {
    var stream: IDBAudioObjectID = 0
    XCTAssertTrue(property(defaultOutputDevice, address("stm#", "inpt"), &stream))
    var rate = address("nsrt")
    var value: Double = 0
    var size = UInt32(MemoryLayout<Double>.size)
    var format = address("sfmt")

    XCTAssertEqual(
      AudioInjectionHAL.getPropertyData(
        hal, object: stream, address: &rate, qualifierDataSize: 0, qualifierData: nil, dataSize: &size, data: &value),
      0x7768_6F3F)
    XCTAssertEqual(
      AudioInjectionHAL.getPropertyDataSize(
        hal, object: stream, address: &rate, qualifierDataSize: 0, qualifierData: nil, dataSize: &size),
      0x7768_6F3F)
    XCTAssertTrue(AudioInjectionHAL.hasProperty(hal, object: stream, address: &format))
    XCTAssertFalse(AudioInjectionHAL.hasProperty(hal, object: stream, address: &rate))
    XCTAssertEqual(
      AudioInjectionHAL.addPropertyListener(hal, object: stream, address: &rate, listener: nil, clientData: nil), noErr)
    XCTAssertEqual(
      AudioInjectionHAL.addPropertyListenerBlock(hal, object: stream, address: &rate, queue: nil, listener: nil), noErr)
  }

  func testOtherObjectsReachTheHAL() {
    var rate = address("nsrt")
    var value: Double = 0
    var size = UInt32(MemoryLayout<Double>.size)

    XCTAssertEqual(
      AudioInjectionHAL.getPropertyData(
        hal, object: defaultOutputDevice, address: &rate, qualifierDataSize: 0, qualifierData: nil, dataSize: &size,
        data: &value),
      noErr)
    XCTAssertEqual(value, withFake { $0.propertyRate })
    XCTAssertTrue(AudioInjectionHAL.hasProperty(hal, object: defaultOutputDevice, address: &rate))
    XCTAssertEqual(
      AudioInjectionHAL.addPropertyListener(hal, object: defaultOutputDevice, address: &rate, listener: nil, clientData: nil),
      31)
    XCTAssertEqual(
      AudioInjectionHAL.addPropertyListenerBlock(hal, object: defaultOutputDevice, address: &rate, queue: nil, listener: nil),
      32)
  }

  // The shim is loaded into every iOS test process idb runs, armed or not.

  private var unarmed: AudioHAL {
    var unarmed = hal
    unarmed.armed = false
    return unarmed
  }

  func testUnarmedCreateRegistersTheCallersOwnIOProc() {
    var handle: UnsafeMutableRawPointer?
    let clientData = UnsafeMutableRawPointer(bitPattern: 0xBEEF)

    XCTAssertEqual(
      AudioInjectionHAL.createIOProcID(
        unarmed, device: 8, proc: originalProc, clientData: clientData, outIOProcID: &handle),
      noErr)

    XCTAssertEqual(withFake { $0.calls }, ["create"])
    XCTAssertEqual(
      withFake { $0.proc.map { unsafeBitCast($0, to: UInt.self) } }, unsafeBitCast(originalProc, to: UInt.self))
    XCTAssertEqual(withFake { $0.clientData }, 0xBEEF)
    XCTAssertEqual(handle, UnsafeMutableRawPointer(bitPattern: 0x1234))

    engine.replace(samples: [.max, .min], sampleRate: 48_000, generation: 1)
    var input: [Float] = [0, 0]
    XCTAssertEqual(callback(8, input: &input), 17)
    XCTAssertEqual(input, [0, 0])
    XCTAssertEqual(withFake { $0.controllerStarts }, 0)

    XCTAssertEqual(AudioInjectionHAL.destroyIOProcID(unarmed, device: 8, ioProcID: handle), noErr)
    XCTAssertEqual(withFake { $0.calls }, ["create", "destroy"])
  }

  func testUnarmedPropertyCallsReachTheHALUnchanged() {
    withFake { $0.hasPropertyAnswer = false }
    var defaultInput = address("dIn ")
    var device: IDBAudioObjectID = 99
    var deviceSize = UInt32(MemoryLayout<IDBAudioObjectID>.size)
    var inputStreams = address("stm#", "inpt")
    var streamBytes: UInt32 = 7

    XCTAssertEqual(
      AudioInjectionHAL.getPropertyData(
        unarmed, object: 1, address: &defaultInput, qualifierDataSize: 0, qualifierData: nil, dataSize: &deviceSize,
        data: &device),
      noErr)
    XCTAssertEqual(
      AudioInjectionHAL.getPropertyDataSize(
        unarmed, object: defaultOutputDevice, address: &inputStreams, qualifierDataSize: 0, qualifierData: nil,
        dataSize: &streamBytes),
      noErr)
    XCTAssertFalse(AudioInjectionHAL.hasProperty(unarmed, object: defaultOutputDevice, address: &inputStreams))
    XCTAssertEqual(
      AudioInjectionHAL.addPropertyListener(
        unarmed, object: 0x7F00_0049, address: &inputStreams, listener: nil, clientData: nil),
      31)
    XCTAssertEqual(
      AudioInjectionHAL.addPropertyListenerBlock(
        unarmed, object: 0x7F00_0049, address: &inputStreams, queue: nil, listener: nil),
      32)

    // The host's own answers, where an armed process would see the synthetic microphone.
    XCTAssertEqual(device, 0)
    XCTAssertEqual(streamBytes, 0)
    XCTAssertEqual(withFake { $0.calls }, ["get", "size", "has", "listen", "listenBlock"])
  }
}
