/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import GRPC

struct FileDrainWriter {

  static func performDrain(taskFuture: FBFuture<FBProcess<NSNull, InputStream, AnyObject>>, sendResponse: (Data) async throws -> Void) async throws {
    let task = try await BridgeFuture.value(taskFuture)
    guard let inputStream = task.stdOut else {
      throw GRPCStatus(code: .internalError, message: "Unable to get stdOut to write")
    }

    inputStream.open()
    defer { inputStream.close() }

    while inputStream.hasBytesAvailable {
      let sixteenKilobytes = 16384
      var buffer = [UInt8](repeating: 0, count: sixteenKilobytes)
      let readBytes = inputStream.read(&buffer, maxLength: sixteenKilobytes)

      guard readBytes >= 0 else {
        let message = "Draining operation failed with stream error: \(inputStream.streamError?.localizedDescription ?? "Unknown")"
        throw GRPCStatus(code: .internalError, message: message)
      }

      let data = Data(buffer)
      try await sendResponse(data)
    }

    let exitCode = try await BridgeFuture.value(task.exitCode).intValue
    if exitCode != 0 {
      throw GRPCStatus(code: .internalError, message: "Draining operation failed with exit code \(exitCode)")
    }
  }

}
