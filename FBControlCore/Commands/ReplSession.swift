/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A running REPL test session. The test process is executing the injected
/// shim's `TestRepl/start`, which binds the control socket at `socketPath` and
/// serves `dlopen`/`dlsym`/call requests. `run` completes when the test process
/// exits, i.e. once the control socket is closed.
public struct ReplSession {
  public let socketPath: String
  public let run: FBFuture<NSNull>

  public init(socketPath: String, run: FBFuture<NSNull>) {
    self.socketPath = socketPath
    self.run = run
  }
}
