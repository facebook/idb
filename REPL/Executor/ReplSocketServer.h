/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

// Shared REPL socket server, used by both the `libRepl` shim (DYLD-injected into
// an xctest process) and the `SimulatorFrameworkBridge` binary. It binds a
// Unix-domain socket, accepts one connection, and serves length-prefixed binary
// property-list frames: each message is a 4-byte big-endian byte count followed
// by that many bytes of a binary property list. Length framing (rather than a
// delimiter) lets payloads carry arbitrary binary, so values round-trip exactly.

// Serves the REPL on `socketPath`. A no-op (returns 0) if `socketPath` is empty.
// Returns 0 on normal completion, non-zero if the socket could not be created.
//
// On connect, before handling commands, the server sends a greeting frame
// (a binary property list `{"type": "greeting", "interfaces": [...]}`) carrying
// `generatedInterfaces` (the host paths of any .swiftinterface files generated
// for the loaded modules; pass an empty array or nil when there are none) so the
// connecting client can learn them.
//
// `keepListening`: when NO, serve a single connection and return (the test and
// simulator contexts, where the host process exits once the session ends). When
// YES, keep the listening socket open and accept a new connection after each one
// closes -- the app context, where the host is a long-lived app that must reset
// and wait for the next client rather than exit.
int FBReplServeSocket(NSString *socketPath, NSArray<NSString *> *generatedInterfaces, BOOL keepListening);

// Sends a `host_command` frame carrying `commandBytes` (the encoded command, e.g.
// a binary property list of a `ReplCommand`) on the active control-socket
// connection, and blocks until the matching `host_result`. Returns that response
// frame's raw bytes -- a binary property list, malloc'd, the caller frees it --
// and writes the byte count to `*outLength`. Returns NULL on failure / when no
// connection is active.
//
// `commandBytes`/`commandLength` are the payload to send (may be NULL/0). Only
// valid to call while a command is executing -- i.e. from injected code running
// inside the served call -- since the protocol is strictly nested and lockstep
// (no other message may be in flight on the socket).
void *FBReplInvokeHostCommand(const void *commandBytes, int commandLength, int *outLength);

// Whether the REPL host process outlives a single session -- i.e. whether
// FBReplServeSocket was started with keepListening:YES (the app context). Injected
// code resolves this with dlsym (like FBReplInvokeHostCommand) to decide how to
// react when the control socket drops mid-command: in the app context it stops the
// submission quietly and lets the app keep running (the server re-accepts) rather
// than terminating the process as the disposable test / simulator hosts do. NO
// until the server starts.
BOOL FBReplHostOutlivesSession(void);
