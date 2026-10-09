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
  public typealias GetPropertyDataSize =
    @convention(c) (
      IDBAudioObjectID, UnsafePointer<IDBAudioObjectPropertyAddress>?, UInt32, UnsafeRawPointer?,
      UnsafeMutablePointer<UInt32>?
    ) -> OSStatus
  public typealias HasProperty = @convention(c) (IDBAudioObjectID, UnsafePointer<IDBAudioObjectPropertyAddress>?) -> Bool
  public typealias AddPropertyListener =
    @convention(c) (
      IDBAudioObjectID, UnsafePointer<IDBAudioObjectPropertyAddress>?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?
    ) -> OSStatus

  public var createIOProcID: CreateIOProcID
  public var destroyIOProcID: DestroyIOProcID
  public var getPropertyData: GetPropertyData
  public var getPropertyDataSize: GetPropertyDataSize
  public var hasProperty: HasProperty
  public var addPropertyListener: AddPropertyListener
  public var addPropertyListenerBlock: AddPropertyListener
  /// Called on the audio thread, so it may only signal work prepared off it.
  public var startController: @convention(c) () -> Void

  public init(
    createIOProcID: CreateIOProcID,
    destroyIOProcID: DestroyIOProcID,
    getPropertyData: GetPropertyData,
    getPropertyDataSize: GetPropertyDataSize,
    hasProperty: HasProperty,
    addPropertyListener: AddPropertyListener,
    addPropertyListenerBlock: AddPropertyListener,
    startController: @convention(c) () -> Void
  ) {
    self.createIOProcID = createIOProcID
    self.destroyIOProcID = destroyIOProcID
    self.getPropertyData = getPropertyData
    self.getPropertyDataSize = getPropertyDataSize
    self.hasProperty = hasProperty
    self.addPropertyListener = addPropertyListener
    self.addPropertyListenerBlock = addPropertyListenerBlock
    self.startController = startController
  }
}

private func fourCC(_ code: StaticString) -> UInt32 {
  code.withUTF8Buffer { $0.reduce(0) { $0 << 8 | UInt32($1) } }
}

private enum Property {
  static let nominalSampleRate = fourCC("nsrt")
  static let defaultInput = fourCC("dIn ")
  static let defaultOutput = fourCC("dOut")
  static let streams = fourCC("stm#")
  static let streamConfiguration = fourCC("slay")
  static let virtualFormat = fourCC("sfmt")
  static let physicalFormat = fourCC("pft ")
  static let direction = fourCC("sdir")
  static let startingChannel = fourCC("stsc")
  static let latency = fourCC("ltnc")
  static let bufferFrameSize = fourCC("fsiz")
  static let globalScope = fourCC("glob")
  static let inputScope = fourCC("inpt")
}

private let systemObject: IDBAudioObjectID = 1
private let syntheticCapacityFrames: UInt32 = 4096
private let defaultSyntheticFrames: UInt32 = 512
private let syntheticStreamBase: IDBAudioObjectID = 0x7F00_0000
private let parameterError: OSStatus = -50
private let unknownPropertyError: OSStatus = 0x7768_6F3F // 'who?'
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
  let syntheticInput: Bool
  var syntheticListening = false
  let syntheticFrames: UInt32
  let syntheticSamples: UnsafeMutablePointer<Float>
  let syntheticList: UnsafeMutablePointer<AudioBufferList>
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
  /// One entry per read of a synthetic stream's latency, which a client makes only to record. The next
  /// IO proc on that device to be created, or failing that the next to call back, claims the entry and
  /// is the recorder. A playback-only IO proc on a device without input is also given a synthetic
  /// buffer, but claims nothing, so it is never filled or counted as having heard the injection.
  let listening = UnsafeMutablePointer<UInt64>.allocate(capacity: listeningSlots)
  var listeningNext: UInt64 = 0
}

private let listeningSlots = 64

// SAFETY: `State` is guarded by its two locks, apart from the atomics.
// patternlint-disable-next-line swift-nonisolated-unsafe
private nonisolated(unsafe) let state: UnsafeMutablePointer<State> = {
  let state = UnsafeMutablePointer<State>.allocate(capacity: 1)
  state.initialize(to: State())
  pthread_mutex_init(&state.pointee.injectionLock, nil)
  pthread_mutex_init(&state.pointee.ioProcLock, nil)
  state.pointee.listening.initialize(repeating: 0, count: listeningSlots)
  return state
}()

public enum AudioInjectionHAL {
  public static func isSyntheticStream(_ object: IDBAudioObjectID) -> Bool {
    object & 0xFF00_0000 == syntheticStreamBase
  }

  static func deviceSampleRate(_ getPropertyData: AudioHAL.GetPropertyData, device: IDBAudioObjectID) -> Double {
    var rate: Double = 0
    return read(getPropertyData, device, Property.nominalSampleRate, into: &rate) && rate > 0 ? rate : defaultSampleRate
  }

  /// Answers a property the synthetic input changes, returning false for any other. With `data` nil
  /// it reports only the size.
  public static func syntheticProperty(
    _ hal: AudioHAL,
    object: IDBAudioObjectID,
    address: UnsafePointer<IDBAudioObjectPropertyAddress>?,
    dataSize: UnsafeMutablePointer<UInt32>?,
    data: UnsafeMutableRawPointer?
  ) -> Bool {
    guard let selector = address?.pointee.selector else {
      return false
    }
    if isSyntheticStream(object) {
      let device = object & ~syntheticStreamBase
      switch selector {
      case Property.virtualFormat, Property.physicalFormat:
        let format = AudioStreamBasicDescription(
          mSampleRate: deviceSampleRate(hal.getPropertyData, device: device), mFormatID: kAudioFormatLinearPCM,
          mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 4, mFramesPerPacket: 1,
          mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        return answer(format, dataSize, data)
      case Property.direction, Property.startingChannel:
        return answer(UInt32(1), dataSize, data)
      case Property.latency:
        let answered = answer(UInt32(0), dataSize, data)
        if answered, data != nil {
          markListening(device)
        }
        return answered
      default:
        return false
      }
    }
    if object == systemObject, selector == Property.defaultInput, defaultDevice(hal, Property.defaultInput) == 0 {
      guard let output = defaultDevice(hal, Property.defaultOutput), output != 0 else {
        return false
      }
      return answer(output, dataSize, data)
    }
    guard address?.pointee.scope == Property.inputScope, needsSyntheticInput(hal, object) else {
      return false
    }
    switch selector {
    case Property.streams:
      return answer(syntheticStreamBase | object, dataSize, data)
    case Property.streamConfiguration:
      let configuration = AudioBufferList(
        mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
      return answer(configuration, dataSize, data)
    default:
      return false
    }
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
    let synthetic = needsSyntheticInput(hal, device)
    var frames: UInt32 = 0
    if synthetic, !read(hal.getPropertyData, device, Property.bufferFrameSize, into: &frames) {
      frames = 0
    }
    let samples = UnsafeMutablePointer<Float>.allocate(capacity: Int(syntheticCapacityFrames))
    let context = UnsafeMutablePointer<IOProcContext>.allocate(capacity: 1)
    context.initialize(
      to: IOProcContext(
        proc: proc, clientData: clientData, device: device, getPropertyData: hal.getPropertyData,
        startController: hal.startController, syntheticInput: synthetic,
        syntheticListening: synthetic && claimListening(device),
        syntheticFrames: frames > 0 ? min(frames, syntheticCapacityFrames) : defaultSyntheticFrames,
        syntheticSamples: samples, syntheticList: .allocate(capacity: 1)))
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
    // Every later callback sees `retired` and returns before it touches the buffers.
    found.pointee.syntheticSamples.deallocate()
    found.pointee.syntheticList.deallocate()
    pthread_mutex_lock(&state.pointee.ioProcLock)
    found.pointee.next = state.pointee.retired
    state.pointee.retired = found
    pthread_mutex_unlock(&state.pointee.ioProcLock)
    return status
  }

  public static func getPropertyData(
    _ hal: AudioHAL,
    object: IDBAudioObjectID,
    address: UnsafePointer<IDBAudioObjectPropertyAddress>?,
    qualifierDataSize: UInt32,
    qualifierData: UnsafeRawPointer?,
    dataSize: UnsafeMutablePointer<UInt32>?,
    data: UnsafeMutableRawPointer?
  ) -> OSStatus {
    if syntheticProperty(hal, object: object, address: address, dataSize: dataSize, data: data) {
      return noErr
    }
    if isSyntheticStream(object) {
      return unknownPropertyError
    }
    return hal.getPropertyData(object, address, qualifierDataSize, qualifierData, dataSize, data)
  }

  public static func getPropertyDataSize(
    _ hal: AudioHAL,
    object: IDBAudioObjectID,
    address: UnsafePointer<IDBAudioObjectPropertyAddress>?,
    qualifierDataSize: UInt32,
    qualifierData: UnsafeRawPointer?,
    dataSize: UnsafeMutablePointer<UInt32>?
  ) -> OSStatus {
    if syntheticProperty(hal, object: object, address: address, dataSize: dataSize, data: nil) {
      return noErr
    }
    if isSyntheticStream(object) {
      return unknownPropertyError
    }
    return hal.getPropertyDataSize(object, address, qualifierDataSize, qualifierData, dataSize)
  }

  public static func hasProperty(
    _ hal: AudioHAL, object: IDBAudioObjectID, address: UnsafePointer<IDBAudioObjectPropertyAddress>?
  ) -> Bool {
    var size: UInt32 = 0
    return syntheticProperty(hal, object: object, address: address, dataSize: &size, data: nil)
      || (!isSyntheticStream(object) && hal.hasProperty(object, address))
  }

  public static func addPropertyListener(
    _ hal: AudioHAL,
    object: IDBAudioObjectID,
    address: UnsafePointer<IDBAudioObjectPropertyAddress>?,
    listener: UnsafeMutableRawPointer?,
    clientData: UnsafeMutableRawPointer?
  ) -> OSStatus {
    return isSyntheticStream(object) ? noErr : hal.addPropertyListener(object, address, listener, clientData)
  }

  public static func addPropertyListenerBlock(
    _ hal: AudioHAL,
    object: IDBAudioObjectID,
    address: UnsafePointer<IDBAudioObjectPropertyAddress>?,
    queue: UnsafeMutableRawPointer?,
    listener: UnsafeMutableRawPointer?
  ) -> OSStatus {
    return isSyntheticStream(object) ? noErr : hal.addPropertyListenerBlock(object, address, queue, listener)
  }

  private static func release(_ context: UnsafeMutablePointer<IOProcContext>) {
    context.pointee.syntheticSamples.deallocate()
    context.pointee.syntheticList.deallocate()
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

  /// Nil when the read fails, which is not the same as a host with no such device.
  private static func defaultDevice(_ hal: AudioHAL, _ selector: UInt32) -> IDBAudioObjectID? {
    var device: IDBAudioObjectID = 0
    return read(hal.getPropertyData, systemObject, selector, into: &device) ? device : nil
  }

  private static func needsSyntheticInput(_ hal: AudioHAL, _ device: IDBAudioObjectID) -> Bool {
    guard device != systemObject, !isSyntheticStream(device), defaultDevice(hal, Property.defaultInput) == 0 else {
      return false
    }
    var address = IDBAudioObjectPropertyAddress(selector: Property.streams, scope: Property.inputScope, element: 0)
    var size: UInt32 = 0
    return hal.getPropertyDataSize(device, &address, 0, nil, &size) == noErr && size == 0
  }

  private static func answer<Value>(
    _ value: Value, _ dataSize: UnsafeMutablePointer<UInt32>?, _ data: UnsafeMutableRawPointer?
  ) -> Bool {
    let size = UInt32(MemoryLayout<Value>.size)
    guard let dataSize, data == nil || dataSize.pointee >= size else {
      return false
    }
    data?.storeBytes(of: value, as: Value.self)
    dataSize.pointee = size
    return true
  }

  private static func markListening(_ device: IDBAudioObjectID) {
    // A free slot is reserved, so an unclaimed mark is never overwritten while one remains. Only with
    // every slot holding an unclaimed mark is the oldest-written one replaced.
    if (0..<listeningSlots).contains(where: { IDBAtomicCompareExchange(state.pointee.listening + $0, 0, UInt64(device)) }) {
      return
    }
    let slot = Int(IDBAtomicAdd(&state.pointee.listeningNext, 1) % UInt64(listeningSlots))
    _ = IDBAtomicExchange(state.pointee.listening + slot, UInt64(device))
  }
}

/// Lock-free, because the audio thread claims too.
private func claimListening(_ device: IDBAudioObjectID) -> Bool {
  (0..<listeningSlots).contains { IDBAtomicCompareExchange(state.pointee.listening + $0, UInt64(device), 0) }
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

  var input = UnsafeMutablePointer(mutating: inputData)
  var listening = true
  if context.pointee.syntheticInput, (input?.pointee.mNumberBuffers ?? 0) == 0 {
    if !context.pointee.syntheticListening {
      context.pointee.syntheticListening = claimListening(device)
    }
    listening = context.pointee.syntheticListening
    // AudioToolbox drops an input buffer that is not exactly one IO cycle, which the output buffer is.
    let outputFrames = outputData.map { $0.pointee.mNumberBuffers > 0 ? frameCapacity($0.pointee.mBuffers) : 0 } ?? 0
    let frames = outputFrames > 0 ? min(outputFrames, syntheticCapacityFrames) : context.pointee.syntheticFrames
    context.pointee.syntheticSamples.update(repeating: 0, count: Int(frames))
    context.pointee.syntheticList.pointee = AudioBufferList(
      mNumberBuffers: 1,
      mBuffers: AudioBuffer(
        mNumberChannels: 1, mDataByteSize: frames * UInt32(MemoryLayout<Float>.size),
        mData: UnsafeMutableRawPointer(context.pointee.syntheticSamples)))
    input = context.pointee.syntheticList
  }
  if listening, let input, input.pointee.mNumberBuffers > 0 {
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
