/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import GRPCCore

struct FileDrainWriter {

  /// Launches `subprocess` and sends its stdout as it is produced, failing if it does not exit cleanly.
  static func performDrain(_ subprocess: Subprocess, logger: any ControlCoreLogger, sendResponse: (Data) async throws -> Void) async throws {
    let completed = try await subprocess.stream(error: .loggerCapturingErrorMessage(logger), exitPolicy: .any, logger: logger, sendResponse)
    try completed.checkExitedCleanly { RPCError(code: .internalError, message: "Draining operation failed with exit code \($0)") }
  }

}
