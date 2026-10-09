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
}

private let recorded = Mutex(Recorded())

private func withFake<Result: Sendable>(_ body: (inout Recorded) -> Result) -> Result {
  recorded.withLock { body(&$0) }
}

private let hal = AudioHAL(
  createIOProcID: { _, proc, clientData, handle in
    withFake {
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
      $0.destroyCount += 1
      return $0.destroyStatus
    }
  },
  getPropertyData: { _, _, _, _, size, data in
    withFake {
      if let size, size.pointee >= MemoryLayout<Double>.size {
        data?.storeBytes(of: $0.propertyRate, as: Double.self)
      }
      return noErr
    }
  },
  startController: { withFake { $0.controllerStarts += 1 } })

private let originalProc: IDBAudioDeviceIOProc = { _, _, _, _, _, _, _ in
  withFake { $0.originalCallbacks += 1 }
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
}
