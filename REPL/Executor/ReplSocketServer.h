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

// Sends a `host_command` on the active control-socket connection and blocks until
// the matching `host_result`, returning that response as a malloc'd JSON C string
// (the caller frees it), or NULL on failure / when no connection is active.
//
// `name` is the command name; `argsJSON` is a JSON object string of arguments (may
// be NULL or "{}"). Only valid to call while a command is executing -- i.e. from
// injected code running inside the served call -- since the protocol is strictly
// nested and lockstep (no other message may be in flight on the socket).
const char *FBReplInvokeHostCommand(const char *name, const char *argsJSON);
