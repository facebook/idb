/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import ShimulatorAudioInjectionCore
@_implementationOnly import ShimulatorAudioInjectionHAL
@_implementationOnly import ShimulatorAudioInjectionPrivate
@_implementationOnly import ShimulatorProtocol
import os

/// Prepared off the audio thread and signalled from it: the IO proc may not start a thread itself.
private let controllerStart: DispatchSourceUserDataOr = {
  let source = DispatchSource.makeUserDataOrSource(queue: .global(qos: .utility))
  source.setEventHandler {
    controllerStart.cancel()
    startClient()
  }
  source.activate()
  return source
}()

private let realHAL = AudioHAL(
  armed: IDBAudioInjectionIsArmed(),
  createIOProcID: AudioDeviceCreateIOProcID,
  destroyIOProcID: AudioDeviceDestroyIOProcID,
  getPropertyData: AudioObjectGetPropertyData,
  getPropertyDataSize: AudioObjectGetPropertyDataSize,
  hasProperty: { object, address in AudioObjectHasProperty(object, address) },
  addPropertyListener: AudioObjectAddPropertyListener,
  addPropertyListenerBlock: AudioObjectAddPropertyListenerBlock,
  startController: { controllerStart.or(data: 1) })

private func startClient() {
  let logger = Logger(subsystem: "com.facebook.idb", category: "audio-injection")
  guard let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"], !udid.isEmpty else {
    logger.error("No simulator UDID is available to find the audio socket")
    return
  }
  let path = ShimulatorWireProtocol.socketPath(capability: ShimulatorAudioInjection.capability, simulatorUDID: udid)
  Thread.detachNewThread {
    ShimulatorClient(
      socketPath: path,
      handler: AudioInjectionController(engine: HALAudioInjectionEngine()),
      log: { message in logger.log("\(message, privacy: .public)") }
    ).run()
  }
}

// Calls from this image to the originals are not interposed, so they reach CoreAudio.
// `@_cdecl`, not `@c @implementation`: the open-source build supports Swift 6.2.

// patternlint-disable-next-line cdecl-unsupported
@_cdecl("IDBAudioDeviceCreateIOProcID")
func IDBAudioDeviceCreateIOProcID(
  _ device: IDBAudioObjectID,
  _ proc: IDBAudioDeviceIOProc?,
  _ clientData: UnsafeMutableRawPointer?,
  _ outIOProcID: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> OSStatus {
  if realHAL.armed {
    _ = controllerStart
  }
  return AudioInjectionHAL.createIOProcID(
    realHAL, device: device, proc: proc, clientData: clientData, outIOProcID: outIOProcID)
}

// patternlint-disable-next-line cdecl-unsupported
@_cdecl("IDBAudioDeviceDestroyIOProcID")
func IDBAudioDeviceDestroyIOProcID(_ device: IDBAudioObjectID, _ ioProcID: UnsafeMutableRawPointer?) -> OSStatus {
  AudioInjectionHAL.destroyIOProcID(realHAL, device: device, ioProcID: ioProcID)
}

// patternlint-disable-next-line cdecl-unsupported
@_cdecl("IDBAudioObjectGetPropertyData")
func IDBAudioObjectGetPropertyData(
  _ object: IDBAudioObjectID,
  _ address: UnsafePointer<IDBAudioObjectPropertyAddress>?,
  _ qualifierDataSize: UInt32,
  _ qualifierData: UnsafeRawPointer?,
  _ dataSize: UnsafeMutablePointer<UInt32>?,
  _ data: UnsafeMutableRawPointer?
) -> OSStatus {
  AudioInjectionHAL.getPropertyData(
    realHAL, object: object, address: address, qualifierDataSize: qualifierDataSize, qualifierData: qualifierData,
    dataSize: dataSize, data: data)
}

// patternlint-disable-next-line cdecl-unsupported
@_cdecl("IDBAudioObjectGetPropertyDataSize")
func IDBAudioObjectGetPropertyDataSize(
  _ object: IDBAudioObjectID,
  _ address: UnsafePointer<IDBAudioObjectPropertyAddress>?,
  _ qualifierDataSize: UInt32,
  _ qualifierData: UnsafeRawPointer?,
  _ dataSize: UnsafeMutablePointer<UInt32>?
) -> OSStatus {
  AudioInjectionHAL.getPropertyDataSize(
    realHAL, object: object, address: address, qualifierDataSize: qualifierDataSize, qualifierData: qualifierData,
    dataSize: dataSize)
}

// patternlint-disable-next-line cdecl-unsupported
@_cdecl("IDBAudioObjectHasProperty")
func IDBAudioObjectHasProperty(_ object: IDBAudioObjectID, _ address: UnsafePointer<IDBAudioObjectPropertyAddress>?) -> Bool {
  AudioInjectionHAL.hasProperty(realHAL, object: object, address: address)
}

// patternlint-disable-next-line cdecl-unsupported
@_cdecl("IDBAudioObjectAddPropertyListener")
func IDBAudioObjectAddPropertyListener(
  _ object: IDBAudioObjectID,
  _ address: UnsafePointer<IDBAudioObjectPropertyAddress>?,
  _ listener: UnsafeMutableRawPointer?,
  _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
  AudioInjectionHAL.addPropertyListener(
    realHAL, object: object, address: address, listener: listener, clientData: clientData)
}

// patternlint-disable-next-line cdecl-unsupported
@_cdecl("IDBAudioObjectAddPropertyListenerBlock")
func IDBAudioObjectAddPropertyListenerBlock(
  _ object: IDBAudioObjectID,
  _ address: UnsafePointer<IDBAudioObjectPropertyAddress>?,
  _ queue: UnsafeMutableRawPointer?,
  _ listener: UnsafeMutableRawPointer?
) -> OSStatus {
  AudioInjectionHAL.addPropertyListenerBlock(realHAL, object: object, address: address, queue: queue, listener: listener)
}
