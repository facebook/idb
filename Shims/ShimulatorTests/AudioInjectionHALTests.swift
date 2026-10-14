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
import Testing

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

@Suite(.serialized)
struct AudioInjectionHALTests {
  private let engine = HALAudioInjectionEngine()

  init() {
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

  @Test
  func injectedSamplesReachTheOriginalCallback() throws {
    let (_, handle) = create(8)
    engine.replace(samples: [.max, .min], sampleRate: 48_000, generation: 1)
    _ = engine.pollProgress()
    var output: [Float] = [0, 0]

    #expect(callback(8, input: &output) == 17)
    #expect(abs(output[0] - 1) <= 0.0001)
    #expect(abs(output[1] + 1) <= 0.0001)
    #expect(withFake { $0.originalCallbacks } == 1)
    #expect(destroy(8, handle) == noErr)
  }

  @Test
  func unknownRateDefersInjectionUntilPollingPreparesIt() {
    let (_, handle) = create(8)
    let samples = (1...48).map { Int16($0 * 100) }
    engine.replace(samples: samples, sampleRate: 48_000, generation: 1)
    var input = Array(repeating: Float(0.25), count: 48)

    #expect(callback(8, input: &input) == 17)
    #expect(input == Array(repeating: Float(0.25), count: 48))
    #expect(engine.pollProgress() == .init(generation: 1, started: false, finished: false))

    #expect(callback(8, input: &input) == 17)
    for frame in input.indices {
      let index = Int(Double(frame) * 48_000 / 44_100)
      let expected = index < samples.count ? Float(samples[index]) / Float(Int16.max) : 0
      #expect(abs(input[frame] - expected) <= 0.0001)
    }
    #expect(engine.pollProgress() == .init(generation: 1, started: true, finished: true))
    #expect(withFake { $0.originalCallbacks } == 2)
    #expect(destroy(8, handle) == noErr)
  }

  @Test
  func pendingRateKeepsTheClipAvailableForAnotherInputProc() {
    let (_, firstHandle) = create(8)
    let samples = (1...48).map { Int16($0 * 100) }
    engine.replace(samples: samples, sampleRate: 48_000, generation: 1)
    _ = engine.pollProgress()
    var first = Array(repeating: Float(0.25), count: 48)
    #expect(callback(8, input: &first) == 17)

    let (_, secondHandle) = create(9)
    var second = Array(repeating: Float(0.25), count: 48)
    #expect(callback(9, input: &second) == 17)
    #expect(second == Array(repeating: Float(0.25), count: 48))
    #expect(engine.pollProgress() == .init(generation: 1, started: true, finished: false))

    #expect(callback(9, input: &second) == 17)
    for frame in second.indices {
      let index = Int(Double(frame) * 48_000 / 44_100)
      let expected = index < samples.count ? Float(samples[index]) / Float(Int16.max) : 0
      #expect(abs(second[frame] - expected) <= 0.0001)
    }
    #expect(engine.pollProgress() == .init(generation: 1, started: true, finished: true))
    #expect(destroy(8, firstHandle) == noErr)
    #expect(destroy(9, secondHandle) == noErr)
  }

  @Test
  func resamplingContinuesAcrossCallbacks() throws {
    let (_, handle) = create(9)
    withFake { $0.propertyRate = 96_000 }
    engine.replace(samples: [.max, 0, .min + 1], sampleRate: 48_000, generation: 1)
    _ = engine.pollProgress()
    var first: [Float] = [9, 9, 9]
    var second: [Float] = [9, 9, 9]

    _ = callback(9, input: &first)
    _ = callback(9, input: &second)

    for (actual, expected) in zip(first + second, [1, 1, 0, 0, -1, -1] as [Float]) {
      #expect(abs(actual - expected) <= 0.0001)
    }
    #expect(destroy(9, handle) == noErr)
  }

  @Test
  func controllerStartsOnlyAfterAnInputCallback() {
    let (_, handle) = create(7)
    #expect(withFake { $0.controllerStarts } == 0)

    #expect(invoke(7) == 17)
    #expect(withFake { $0.controllerStarts } == 0)

    var input: [Float] = [0]
    #expect(callback(7, input: &input) == 17)
    #expect(withFake { $0.controllerStarts } == 1)
    #expect(destroy(7, handle) == noErr)
  }

  @Test
  func zeroCapacityBufferIsNotWritten() throws {
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
        #expect(invoke(8, list.unsafePointer) == 17)
      }
    }

    #expect(abs(output[0] - 1) <= 0.0001)
    #expect(abs(output[1] + 1) <= 0.0001)
    #expect(canary == 42)
    #expect(destroy(8, handle) == noErr)
  }

  @Test
  func failedDestroyKeepsForwardingCallbacks() {
    let (_, handle) = create(9)
    withFake { $0.destroyStatus = -7 }

    #expect(destroy(9, handle) == -7)
    #expect(invoke(9) == 17)
    #expect(withFake { $0.originalCallbacks } == 1)

    withFake { $0.destroyStatus = noErr }
    #expect(destroy(9, handle) == noErr)
  }

  @Test
  func callbackRacingADestroyNeverReachesTheApp() {
    let (_, handle) = create(9)
    #expect(destroy(9, handle) == noErr)

    var input: [Float] = [0]
    #expect(callback(9, input: &input) == noErr)
    #expect(withFake { $0.originalCallbacks } == 0)
  }

  @Test
  func finishedStaysReportedUntilTheNextInjection() throws {
    let (_, handle) = create(8)
    engine.replace(samples: [.max, .min], sampleRate: 48_000, generation: 1)
    _ = engine.pollProgress()
    var output: [Float] = [0, 0]
    _ = callback(8, input: &output)

    for _ in 0..<2 {
      #expect(engine.pollProgress() == .init(generation: 1, started: true, finished: true))
    }

    engine.replace(samples: [.max, .min], sampleRate: 48_000, generation: 2)
    #expect(engine.pollProgress() == .init(generation: 2, started: false, finished: false))
    #expect(destroy(8, handle) == noErr)
  }

  @Test
  func createFailureIsReturnedWithoutAHandle() {
    withFake { $0.createStatus = -7 }

    let (status, handle) = create(11)

    #expect(status == -7)
    #expect(handle == nil)
  }

  @Test
  func successfulCreateWithoutAHandleIsAnError() {
    withFake { $0.createdHandle = 0 }

    let (status, handle) = create(11)

    #expect(status == -50)
    #expect(handle == nil)
  }

  @Test
  func deviceWithoutInputOffersTheSyntheticStream() {
    var device: IDBAudioObjectID = 0
    #expect(property(1, address("dIn "), &device))
    #expect(device == defaultOutputDevice)

    var stream: IDBAudioObjectID = 0
    #expect(property(defaultOutputDevice, address("stm#", "inpt"), &stream))
    #expect(AudioInjectionHAL.isSyntheticStream(stream))

    var format = AudioStreamBasicDescription()
    #expect(property(stream, address("sfmt"), &format))
    #expect(format.mSampleRate == withFake { $0.propertyRate })
    #expect(format.mFormatID == kAudioFormatLinearPCM)
    #expect(format.mChannelsPerFrame == 1)
    #expect(format.mBitsPerChannel == 32)

    withFake { $0.inputStreamBytes = UInt32(MemoryLayout<IDBAudioObjectID>.size) }
    #expect(!property(defaultOutputDevice, address("stm#", "inpt"), &stream))
  }

  @Test
  func deviceWithoutInputReceivesInjectedSamples() throws {
    var stream: IDBAudioObjectID = 0
    #expect(property(104, address("stm#", "inpt"), &stream))
    var latency: UInt32 = 1
    #expect(property(stream, address("ltnc"), &latency))
    let (status, handle) = create(104, capturingProc)
    #expect(status == noErr)
    engine.replace(samples: [.max, .min], sampleRate: 44_100, generation: 1)
    _ = engine.pollProgress()
    var output: [Float] = [0, 0, 0, 0]

    let result = output.withUnsafeMutableBytes { bytes in
      var list = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
      return invoke(104, output: &list)
    }

    #expect(result == 17)
    #expect(abs(withFake { $0.capturedInput }[0] - 1) <= 0.0001)
    #expect(abs(withFake { $0.capturedInput }[1] + 1) <= 0.0001)
    #expect(withFake { $0.capturedInputBytes } == 2 * 4)
    #expect(withFake { $0.controllerStarts } == 1)
    #expect(destroy(104, handle) == noErr)
  }

  @Test
  func playbackOnlyDeviceWithoutInputIsNotFilled() throws {
    let (_, handle) = create(105, capturingProc)
    engine.replace(samples: [.max, .min], sampleRate: 44_100, generation: 1)
    _ = engine.pollProgress()

    #expect(invoke(105) == 17)
    #expect(withFake { $0.capturedInput }.first == 0)
    #expect(withFake { $0.controllerStarts } == 0)
    #expect(!engine.pollProgress().started)
    #expect(destroy(105, handle) == noErr)
  }

  @Test
  func hostWithAMicrophoneIsLeftAlone() {
    withFake { $0.defaultInputDevice = 80 }
    var answer: IDBAudioObjectID = 0

    #expect(!property(1, address("dIn "), &answer))
    #expect(!property(defaultOutputDevice, address("stm#", "inpt"), &answer))
  }

  @Test
  func failedDefaultInputReadIsLeftAlone() {
    withFake { $0.defaultInputStatus = -7 }
    var answer: IDBAudioObjectID = 0

    #expect(!property(1, address("dIn "), &answer))
    #expect(!property(defaultOutputDevice, address("stm#", "inpt"), &answer))
  }

  @Test
  func latencyProbeWithoutReadingItDoesNotMakeARecorder() throws {
    var stream: IDBAudioObjectID = 0
    #expect(property(106, address("stm#", "inpt"), &stream))
    var latency = address("ltnc")
    var size: UInt32 = 0
    #expect(
      AudioInjectionHAL.getPropertyDataSize(
        hal, object: stream, address: &latency, qualifierDataSize: 0, qualifierData: nil, dataSize: &size) == noErr)
    #expect(AudioInjectionHAL.hasProperty(hal, object: stream, address: &latency))
    let (_, handle) = create(106, capturingProc)
    engine.replace(samples: [.max, .min], sampleRate: 44_100, generation: 1)
    _ = engine.pollProgress()

    #expect(invoke(106) == 17)
    #expect(withFake { $0.capturedInput }.first == 0)
    #expect(withFake { $0.controllerStarts } == 0)
    #expect(destroy(106, handle) == noErr)
  }

  @Test
  func recordersThatAllReadLatencyBeforeCreatingAreAllFilled() throws {
    var stream: IDBAudioObjectID = 0
    #expect(property(109, address("stm#", "inpt"), &stream))
    var latency: UInt32 = 1
    for _ in 0..<9 {
      #expect(property(stream, address("ltnc"), &latency))
    }
    var handles: [UnsafeMutableRawPointer?] = []
    for _ in 0..<9 {
      handles.append(create(109, capturingProc).1)
    }
    engine.replace(samples: [.max, .min], sampleRate: 44_100, generation: 1)
    _ = engine.pollProgress()

    #expect(invoke(109) == 17)
    #expect(abs((withFake { $0.capturedInput }.first ?? 0) - 1) <= 0.0001)
    for handle in handles {
      #expect(destroy(109, handle) == noErr)
    }
  }

  @Test
  func aRecorderIndicationEndsWithTheRecorder() throws {
    var stream: IDBAudioObjectID = 0
    #expect(property(107, address("stm#", "inpt"), &stream))
    var latency: UInt32 = 1
    #expect(property(stream, address("ltnc"), &latency))
    let (_, recorder) = create(107, capturingProc)
    #expect(destroy(107, recorder) == noErr)

    let (_, player) = create(107, capturingProc)
    engine.replace(samples: [.max, .min], sampleRate: 44_100, generation: 1)
    _ = engine.pollProgress()

    #expect(invoke(107) == 17)
    #expect(withFake { $0.capturedInput }.first == 0)
    #expect(!engine.pollProgress().started)
    #expect(destroy(107, player) == noErr)
  }

  @Test
  func aRecorderThatReadsLatencyAfterCreatingItsIOProcIsFilled() throws {
    var stream: IDBAudioObjectID = 0
    #expect(property(108, address("stm#", "inpt"), &stream))
    let (_, handle) = create(108, capturingProc)
    var latency: UInt32 = 1
    #expect(property(stream, address("ltnc"), &latency))
    engine.replace(samples: [.max, .min], sampleRate: 44_100, generation: 1)
    _ = engine.pollProgress()

    #expect(invoke(108) == 17)
    #expect(abs((withFake { $0.capturedInput }.first ?? 0) - 1) <= 0.0001)
    #expect(destroy(108, handle) == noErr)
  }

  @Test
  func syntheticStreamAnswersOnlyItsOwnProperties() {
    var stream: IDBAudioObjectID = 0
    #expect(property(defaultOutputDevice, address("stm#", "inpt"), &stream))
    var rate = address("nsrt")
    var value: Double = 0
    var size = UInt32(MemoryLayout<Double>.size)
    var format = address("sfmt")

    #expect(
      AudioInjectionHAL.getPropertyData(
        hal, object: stream, address: &rate, qualifierDataSize: 0, qualifierData: nil, dataSize: &size, data: &value) == 0x7768_6F3F)
    #expect(
      AudioInjectionHAL.getPropertyDataSize(
        hal, object: stream, address: &rate, qualifierDataSize: 0, qualifierData: nil, dataSize: &size) == 0x7768_6F3F)
    #expect(AudioInjectionHAL.hasProperty(hal, object: stream, address: &format))
    #expect(!AudioInjectionHAL.hasProperty(hal, object: stream, address: &rate))
    #expect(
      AudioInjectionHAL.addPropertyListener(hal, object: stream, address: &rate, listener: nil, clientData: nil) == noErr)
    #expect(
      AudioInjectionHAL.addPropertyListenerBlock(hal, object: stream, address: &rate, queue: nil, listener: nil) == noErr)
  }

  @Test
  func otherObjectsReachTheHAL() {
    var rate = address("nsrt")
    var value: Double = 0
    var size = UInt32(MemoryLayout<Double>.size)

    #expect(
      AudioInjectionHAL.getPropertyData(
        hal, object: defaultOutputDevice, address: &rate, qualifierDataSize: 0, qualifierData: nil, dataSize: &size,
        data: &value) == noErr)
    #expect(value == withFake { $0.propertyRate })
    #expect(AudioInjectionHAL.hasProperty(hal, object: defaultOutputDevice, address: &rate))
    #expect(
      AudioInjectionHAL.addPropertyListener(hal, object: defaultOutputDevice, address: &rate, listener: nil, clientData: nil) == 31)
    #expect(
      AudioInjectionHAL.addPropertyListenerBlock(hal, object: defaultOutputDevice, address: &rate, queue: nil, listener: nil) == 32)
  }

  // The shim is loaded into every iOS test process idb runs, armed or not.

  private var unarmed: AudioHAL {
    var unarmed = hal
    unarmed.armed = false
    return unarmed
  }

  @Test
  func unarmedCreateRegistersTheCallersOwnIOProc() {
    var handle: UnsafeMutableRawPointer?
    let clientData = UnsafeMutableRawPointer(bitPattern: 0xBEEF)

    #expect(
      AudioInjectionHAL.createIOProcID(
        unarmed, device: 8, proc: originalProc, clientData: clientData, outIOProcID: &handle) == noErr)

    #expect(withFake { $0.calls } == ["create"])
    #expect(
      withFake { $0.proc.map { unsafeBitCast($0, to: UInt.self) } } == unsafeBitCast(originalProc, to: UInt.self))
    #expect(withFake { $0.clientData } == 0xBEEF)
    #expect(handle == UnsafeMutableRawPointer(bitPattern: 0x1234))

    engine.replace(samples: [.max, .min], sampleRate: 48_000, generation: 1)
    var input: [Float] = [0, 0]
    #expect(callback(8, input: &input) == 17)
    #expect(input == [0, 0])
    #expect(withFake { $0.controllerStarts } == 0)

    #expect(AudioInjectionHAL.destroyIOProcID(unarmed, device: 8, ioProcID: handle) == noErr)
    #expect(withFake { $0.calls } == ["create", "destroy"])
  }

  @Test
  func unarmedPropertyCallsReachTheHALUnchanged() {
    withFake { $0.hasPropertyAnswer = false }
    var defaultInput = address("dIn ")
    var device: IDBAudioObjectID = 99
    var deviceSize = UInt32(MemoryLayout<IDBAudioObjectID>.size)
    var inputStreams = address("stm#", "inpt")
    var streamBytes: UInt32 = 7

    #expect(
      AudioInjectionHAL.getPropertyData(
        unarmed, object: 1, address: &defaultInput, qualifierDataSize: 0, qualifierData: nil, dataSize: &deviceSize,
        data: &device) == noErr)
    #expect(
      AudioInjectionHAL.getPropertyDataSize(
        unarmed, object: defaultOutputDevice, address: &inputStreams, qualifierDataSize: 0, qualifierData: nil,
        dataSize: &streamBytes) == noErr)
    #expect(!AudioInjectionHAL.hasProperty(unarmed, object: defaultOutputDevice, address: &inputStreams))
    #expect(
      AudioInjectionHAL.addPropertyListener(
        unarmed, object: 0x7F00_0049, address: &inputStreams, listener: nil, clientData: nil) == 31)
    #expect(
      AudioInjectionHAL.addPropertyListenerBlock(
        unarmed, object: 0x7F00_0049, address: &inputStreams, queue: nil, listener: nil) == 32)

    // The host's own answers, where an armed process would see the synthetic microphone.
    #expect(device == 0)
    #expect(streamBytes == 0)
    #expect(withFake { $0.calls } == ["get", "size", "has", "listen", "listenBlock"])
  }
}
