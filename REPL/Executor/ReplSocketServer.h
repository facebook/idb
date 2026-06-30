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
//
// On connect, before handling commands, the server sends a one-line JSON
// greeting `{"interfaces": [...]}` carrying `generatedInterfaces` (the host paths
// of any .swiftinterface files generated for the loaded modules; pass an empty
// array or nil when there are none) so the connecting client can learn them.
int FBReplServeSocket(NSString *socketPath, NSArray<NSString *> *generatedInterfaces);
