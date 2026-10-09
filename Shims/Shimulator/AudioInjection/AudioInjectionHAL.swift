/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreAudio
import Foundation
import ShimulatorAudioInjectionCore
import ShimulatorAudioInjectionPrivate

public struct AudioHAL: Sendable {
  public typealias CreateIOProcID =
    @convention(c) (
      IDBAudioObjectID, IDBAudioDeviceIOProc?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    ) -> OSStatus
  public typealias DestroyIOProcID = @convention(c) (IDBAudioObjectID, UnsafeMutableRawPointer?) -> OSStatus
  public typealias GetPropertyData =
    @convention(c) (
      IDBAudioObjectID, UnsafePointer<IDBAudioObjectPropertyAddress>?, UInt32, UnsafeRawPointer?,
      UnsafeMutablePointer<UInt32>?, UnsafeMutableRawPointer?
    ) -> OSStatus

  public var createIOProcID: CreateIOProcID
  public var destroyIOProcID: DestroyIOProcID
  public var getPropertyData: GetPropertyData
  /// Called on the audio thread, so it may only signal work prepared off it.
  public var startController: @convention(c) () -> Void

  public init(
    createIOProcID: CreateIOProcID,
    destroyIOProcID: DestroyIOProcID,
    getPropertyData: GetPropertyData,
    startController: @convention(c) () -> Void
  ) {
    self.createIOProcID = createIOProcID
    self.destroyIOProcID = destroyIOProcID
    self.getPropertyData = getPropertyData
    self.startController = startController
  }
}

private func fourCC(_ code: StaticString) -> UInt32 {
  code.withUTF8Buffer { $0.reduce(0) { $0 << 8 | UInt32($1) } }
}

private enum Property {
  static let nominalSampleRate = fourCC("nsrt")
  static let globalScope = fourCC("glob")
}

private let parameterError: OSStatus = -50
private let defaultSampleRate: Double = 48_000
private let int16ToFloat = 1 / Float(Int16.max)

private struct IOProcContext {
  let proc: IDBAudioDeviceIOProc
  let clientData: UnsafeMutableRawPointer?
  let device: IDBAudioObjectID
  var ioProcID: UnsafeMutableRawPointer?
  let getPropertyData: AudioHAL.GetPropertyData
  let startController: @convention(c) () -> Void
  /// The device's nominal rate as a bit pattern, read on the client thread and used on the audio thread.
  var sampleRateBits: UInt64 = 0
  var position: Double = 0
  var generation: Int64 = -1
  var started = false
  var finished = false
  var activeCallbacks: UInt64 = 0
  var retired: UInt64 = 0
  var controllerStarted: UInt64 = 0
  var next: UnsafeMutablePointer<IOProcContext>?
}

private struct State {
  /// Guards the installed samples and every context's playback fields. The audio thread only
  /// try-locks it, and skips the fill rather than wait.
  var injectionLock = pthread_mutex_t()
  var samples: UnsafeMutablePointer<Int16>?
  var sampleCount = 0
  var sampleRate = defaultSampleRate
  var generation: Int64 = -1
  var startedGeneration: Int64 = -1
  var finishedGeneration: Int64 = -1
  /// Guards the context lists. Never taken on the audio thread.
  var ioProcLock = pthread_mutex_t()
  var contexts: UnsafeMutablePointer<IOProcContext>?
  /// Destroyed contexts, kept for the life of the process: a callback can hold one as `clientData`
  /// before it has counted itself in, and has to find it retired rather than freed.
  var retired: UnsafeMutablePointer<IOProcContext>?
}

// SAFETY: `State` is guarded by its two locks, apart from the atomics.
// patternlint-disable-next-line swift-nonisolated-unsafe
private nonisolated(unsafe) let state: UnsafeMutablePointer<State> = {
  let state = UnsafeMutablePointer<State>.allocate(capacity: 1)
  state.initialize(to: State())
  pthread_mutex_init(&state.pointee.injectionLock, nil)
  pthread_mutex_init(&state.pointee.ioProcLock, nil)
  return state
}()

public enum AudioInjectionHAL {
  static func deviceSampleRate(_ getPropertyData: AudioHAL.GetPropertyData, device: IDBAudioObjectID) -> Double {
    var rate: Double = 0
    return read(getPropertyData, device, Property.nominalSampleRate, into: &rate) && rate > 0 ? rate : defaultSampleRate
  }

  public static func createIOProcID(
    _ hal: AudioHAL,
    device: IDBAudioObjectID,
    proc: IDBAudioDeviceIOProc?,
    clientData: UnsafeMutableRawPointer?,
    outIOProcID: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
  ) -> OSStatus {
    guard let proc, let outIOProcID else {
      return proc == nil ? hal.createIOProcID(device, proc, clientData, outIOProcID) : parameterError
    }
    // Creation holds the lock the client thread's sample-rate read does: a HAL property read made
    // while an IO proc is being created disturbs the device.
    pthread_mutex_lock(&state.pointee.ioProcLock)
    defer { pthread_mutex_unlock(&state.pointee.ioProcLock) }
    let context = UnsafeMutablePointer<IOProcContext>.allocate(capacity: 1)
    context.initialize(
      to: IOProcContext(
        proc: proc, clientData: clientData, device: device, getPropertyData: hal.getPropertyData,
        startController: hal.startController))
    var status = hal.createIOProcID(device, trampoline, context, outIOProcID)
    if status == noErr, outIOProcID.pointee == nil {
      status = parameterError
    }
    guard status == noErr else {
      release(context)
      return status
    }
    context.pointee.ioProcID = outIOProcID.pointee
    context.pointee.next = state.pointee.contexts
    state.pointee.contexts = context
    return noErr
  }

  public static func destroyIOProcID(
    _ hal: AudioHAL, device: IDBAudioObjectID, ioProcID: UnsafeMutableRawPointer?
  ) -> OSStatus {
    // Held across the HAL's own destroy, so a concurrent creation cannot be handed the same opaque
    // ID until this one's context is unlinked.
    pthread_mutex_lock(&state.pointee.ioProcLock)
    let status = hal.destroyIOProcID(device, ioProcID)
    guard status == noErr else {
      pthread_mutex_unlock(&state.pointee.ioProcLock)
      return status
    }
    var previous: UnsafeMutablePointer<IOProcContext>?
    var found = state.pointee.contexts
    while let context = found, context.pointee.ioProcID != ioProcID || context.pointee.device != device {
      previous = context
      found = context.pointee.next
    }
    if let found {
      if let previous {
        previous.pointee.next = found.pointee.next
      } else {
        state.pointee.contexts = found.pointee.next
      }
      _ = IDBAtomicExchange(&found.pointee.retired, 1)
    }
    pthread_mutex_unlock(&state.pointee.ioProcLock)
    guard let found else {
      return status
    }
    while IDBAtomicLoad(&found.pointee.activeCallbacks) > 0 {
      sched_yield()
    }
    pthread_mutex_lock(&state.pointee.ioProcLock)
    found.pointee.next = state.pointee.retired
    state.pointee.retired = found
    pthread_mutex_unlock(&state.pointee.ioProcLock)
    return status
  }

  private static func release(_ context: UnsafeMutablePointer<IOProcContext>) {
    context.deinitialize(count: 1)
    context.deallocate()
  }

  private static func read<Value>(
    _ getPropertyData: AudioHAL.GetPropertyData, _ object: IDBAudioObjectID, _ selector: UInt32,
    into value: inout Value
  ) -> Bool {
    var address = IDBAudioObjectPropertyAddress(selector: selector, scope: Property.globalScope, element: 0)
    var size = UInt32(MemoryLayout<Value>.size)
    return withUnsafeMutableBytes(of: &value) { getPropertyData(object, &address, 0, nil, &size, $0.baseAddress) } == noErr
  }
}

private func frameCapacity(_ buffer: AudioBuffer) -> UInt32 {
  buffer.mData == nil ? 0 : buffer.mDataByteSize / UInt32(MemoryLayout<Float>.size) / max(buffer.mNumberChannels, 1)
}

private func fill(_ list: UnsafeMutablePointer<AudioBufferList>, deviceRate: Double, _ context: UnsafeMutablePointer<IOProcContext>) {
  guard pthread_mutex_trylock(&state.pointee.injectionLock) == 0 else {
    return
  }
  defer { pthread_mutex_unlock(&state.pointee.injectionLock) }
  guard let samples = state.pointee.samples else {
    return
  }
  let buffers = UnsafeMutableAudioBufferListPointer(list)
  var frames = UInt32.max
  for buffer in buffers where frameCapacity(buffer) > 0 {
    frames = min(frames, frameCapacity(buffer))
  }
  guard frames != .max else {
    return
  }
  if context.pointee.generation != state.pointee.generation {
    context.pointee.generation = state.pointee.generation
    context.pointee.position = 0
    context.pointee.started = false
    context.pointee.finished = false
  }
  guard deviceRate > 0 else {
    return
  }

  // Each buffer is one channel group of the same frames, so each starts from the same position.
  let step = state.pointee.sampleRate / deviceRate
  var position = context.pointee.position
  for buffer in buffers {
    guard let data = buffer.mData, frameCapacity(buffer) > 0 else {
      continue
    }
    let channels = Int(max(buffer.mNumberChannels, 1))
    let output = data.assumingMemoryBound(to: Float.self)
    position = context.pointee.position
    for frame in 0..<Int(frames) {
      let index = Int(position)
      let value = index < state.pointee.sampleCount ? Float(samples[index]) * int16ToFloat : 0
      for channel in 0..<channels {
        output[frame * channels + channel] = value
      }
      position += step
    }
  }

  context.pointee.position = position
  context.pointee.started = true
  state.pointee.startedGeneration = state.pointee.generation
  if position >= Double(state.pointee.sampleCount) {
    context.pointee.finished = true
    state.pointee.finishedGeneration = state.pointee.generation
  }
}

private func trampoline(
  device: IDBAudioObjectID,
  now: UnsafePointer<AudioTimeStamp>?,
  inputData: UnsafePointer<AudioBufferList>?,
  inputTime: UnsafePointer<AudioTimeStamp>?,
  outputData: UnsafeMutablePointer<AudioBufferList>?,
  outputTime: UnsafePointer<AudioTimeStamp>?,
  clientData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let context = clientData?.assumingMemoryBound(to: IOProcContext.self) else {
    return noErr
  }
  // Counted before `retired` is read, so a destroy either waits for this callback or this callback
  // sees `retired` and leaves. Lock-free, because this is the audio thread.
  _ = IDBAtomicAdd(&context.pointee.activeCallbacks, 1)
  defer { _ = IDBAtomicAdd(&context.pointee.activeCallbacks, -1) }
  guard IDBAtomicLoad(&context.pointee.retired) == 0 else {
    return noErr
  }

  let input = UnsafeMutablePointer(mutating: inputData)
  if let input, input.pointee.mNumberBuffers > 0 {
    if IDBAtomicExchange(&context.pointee.controllerStarted, 1) == 0 {
      context.pointee.startController()
    }
    let rate = Double(bitPattern: IDBAtomicLoad(&context.pointee.sampleRateBits))
    fill(input, deviceRate: rate, context)
  }
  return context.pointee.proc(device, now, input, inputTime, outputData, outputTime, context.pointee.clientData)
}

public struct HALAudioInjectionEngine: AudioInjectionEngine {
  public init() {}

  public func replace(samples: [Int16], sampleRate: Double, generation: Int64) {
    let copy = UnsafeMutablePointer<Int16>.allocate(capacity: samples.count)
    copy.initialize(from: samples, count: samples.count)
    install(copy, count: samples.count, sampleRate: sampleRate, generation: generation)
  }

  public func clear() {
    install(nil, count: 0, sampleRate: defaultSampleRate, generation: -1)
  }

  private func install(_ samples: UnsafeMutablePointer<Int16>?, count: Int, sampleRate: Double, generation: Int64) {
    pthread_mutex_lock(&state.pointee.injectionLock)
    let previous = state.pointee.samples
    state.pointee.samples = samples
    state.pointee.sampleCount = count
    state.pointee.sampleRate = sampleRate
    state.pointee.generation = generation
    state.pointee.startedGeneration = -1
    state.pointee.finishedGeneration = -1
    pthread_mutex_unlock(&state.pointee.injectionLock)
    previous?.deallocate()
  }

  public func pollProgress() -> AudioInjectionProgress {
    pthread_mutex_lock(&state.pointee.ioProcLock)
    var context = state.pointee.contexts
    while let current = context {
      if IDBAtomicLoad(&current.pointee.sampleRateBits) == 0 {
        let rate = AudioInjectionHAL.deviceSampleRate(current.pointee.getPropertyData, device: current.pointee.device)
        _ = IDBAtomicExchange(&current.pointee.sampleRateBits, rate.bitPattern)
      }
      context = current.pointee.next
    }

    pthread_mutex_lock(&state.pointee.injectionLock)
    let generation = state.pointee.generation
    let started = generation >= 0 && state.pointee.startedGeneration == generation
    var anyUnfinished = false
    context = state.pointee.contexts
    while let current = context {
      anyUnfinished =
        anyUnfinished
        || (current.pointee.generation == generation && !current.pointee.finished)
      context = current.pointee.next
    }
    // Freeing the samples ends playback but keeps the generation markers, so later polls for this
    // generation still report it finished.
    let finished =
      started && state.pointee.finishedGeneration == generation && (state.pointee.samples == nil || !anyUnfinished)
    let played = finished ? state.pointee.samples : nil
    if played != nil {
      state.pointee.samples = nil
      state.pointee.sampleCount = 0
    }
    pthread_mutex_unlock(&state.pointee.injectionLock)
    pthread_mutex_unlock(&state.pointee.ioProcLock)
    played?.deallocate()
    return AudioInjectionProgress(generation: generation, started: started, finished: finished)
  }
}
