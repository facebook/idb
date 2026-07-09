/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <pthread.h>

#import <Foundation/Foundation.h>

#import <ReplExecutor/ReplSocketServer.h>

// The `app` REPL context: `libRepl` is injected into a launched app via
// DYLD_INSERT_LIBRARIES, and this constructor starts the control-socket server
// inside it. In the test / simulator contexts the host calls FBReplServeSocket
// explicitly (an xctest method, or SimulatorFrameworkBridge); an app has no such
// host, so libRepl must start itself on load.
//
// Gated on IDB_REPL_APP_AUTOSTART so libRepl stays inert everywhere else -- the
// test / simulator contexts don't set it, nor does any unrelated process that
// happens to inherit DYLD_INSERT_LIBRARIES.

static void *ReplAppServeThread(void *context)
{
  NSString *socketPath = (NSString *)context; // owned; released when the server returns
  @autoreleasepool {
    // keepListening: the app outlives any single session, so reset and wait for
    // the next client after each disconnect rather than returning.
    FBReplServeSocket(socketPath, @[], YES);
  }
  [socketPath release];
  return NULL;
}

// A constructor is unavoidable here: nothing in an injected app calls into
// libRepl, so it must start itself on load. It is gated on IDB_REPL_APP_AUTOSTART
// and returns immediately (near-zero startup cost) in every other process.
// patternlint-disable-next-line static-initializer-constructor-attribute
__attribute__((constructor)) static void ReplAppAutostart(void)
{
  @autoreleasepool {
    NSDictionary<NSString *, NSString *> *environment = [[NSProcessInfo processInfo] environment];
    if (![environment[@"IDB_REPL_APP_AUTOSTART"] isEqualToString:@"1"]) {
      return;
    }
    NSString *socketPath = [environment[@"IDB_REPL_SOCKET_PATH"] copy];
    if (socketPath.length == 0) {
      [socketPath release];
      return;
    }

    // Stop the injection + autostart from cascading into any child processes the
    // app spawns (they would otherwise try to bind the same socket).
    unsetenv("DYLD_INSERT_LIBRARIES");
    unsetenv("IDB_REPL_APP_AUTOSTART");

    // Serve on a detached background thread: the app needs its main thread for its
    // run loop / UI, and FBReplServeSocket blocks for the session's lifetime.
    pthread_t thread;
    if (pthread_create(&thread, NULL, ReplAppServeThread, (void *)socketPath) == 0) {
      pthread_detach(thread);
    } else {
      [socketPath release];
    }
  }
}
