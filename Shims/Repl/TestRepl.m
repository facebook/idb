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
  // The socket/dylib-running logic is shared. The only REPL piece specific to
  // `libRepl` is this XCTest entry point, which the REPL driver triggers as the
  // `TestRepl/start` test.
  FBReplServeSocketFromEnvironment();
}

@end
