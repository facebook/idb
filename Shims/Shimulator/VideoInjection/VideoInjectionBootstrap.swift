/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import ShimulatorProtocol
@_implementationOnly import ShimulatorVideoInjectionCore

private struct CameraEngine: VideoInjectionEngine {
  func play(fileURL: URL, frontFileURL: URL?, loops: Bool, generation: Int64) throws {
    if let unplayable = VirtualCamera.shared.play(fileURL, front: frontFileURL, loops: loops, generation: generation) {
      throw videoError(2, "\(unplayable.lastPathComponent) holds no playable video track")
    }
  }

  func clear() {
    _ = VirtualCamera.shared.play(nil, front: nil, loops: true, generation: -1)
  }

  func pollProgress() -> VideoInjectionProgress {
    VirtualCamera.shared.progress
  }
}

/// Started by the camera the first time the process enumerates it, so only a process that uses the
/// camera connects.
let videoInjectionClientStarted: Void = {
  guard let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"], !udid.isEmpty else {
    return debug("No simulator UDID is available to find the video socket")
  }
  let path = ShimulatorWireProtocol.socketPath(capability: ShimulatorVideoInjection.capability, simulatorUDID: udid)
  Thread.detachNewThread {
    ShimulatorClient(socketPath: path, handler: VideoInjectionController(engine: CameraEngine()), log: { debug($0) }).run()
  }
}()
