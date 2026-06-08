/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "TestRepl.h"

#import <ReplExecutor/ReplSocketServer.h>

@implementation TestRepl

- (void)start
{
  // Start the shared ReplExecutor with the requested socket path.
  NSString *socketPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"IDB_REPL_SOCKET_PATH"];
  FBReplServeSocket(socketPath);
}

@end
