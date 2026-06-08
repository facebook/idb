/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

// Shared REPL socket server, used by both the `libRepl` shim (DYLD-injected into
// an xctest process) and the `SimulatorFrameworkBridge` binary. It binds a
// Unix-domain socket, accepts one connection, and serves newline-delimited JSON
// commands.

// Serves the REPL on `socketPath`. A no-op (returns 0) if `socketPath` is empty.
// Returns 0 on normal completion, non-zero if the socket could not be created.
int FBReplServeSocket(NSString *socketPath);

// Reads the socket path from the `IDB_REPL_SOCKET_PATH` environment variable and
// serves the REPL there via `FBReplServeSocket`. A no-op if the variable is
// unset or empty, so running it outside of a REPL session does nothing.
int FBReplServeSocketFromEnvironment(void);
