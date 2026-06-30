/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "TestRepl.h"

#import <ReplExecutor/ReplSocketServer.h>

// Walks the target image's Swift metadata and writes <Module>.swiftinterface
// file(s); returns a malloc'd path the caller must free, or NULL.
extern const char *FBReplGenerateSwiftInterface(const char *outDir, const char *imageFilter);

@implementation TestRepl

- (void)start
{
  NSDictionary<NSString *, NSString *> *environment = [[NSProcessInfo processInfo] environment];

  NSString *interfaceDir = environment[@"IDB_REPL_GEN_INTERFACE_DIR"];
  if (interfaceDir.length > 0) {
    NSString *imageFilter = environment[@"IDB_REPL_PROBE_IMAGE"] ?: @"";
    const char *generated =
    FBReplGenerateSwiftInterface(interfaceDir.fileSystemRepresentation, imageFilter.UTF8String);
    if (generated) {
      NSLog(@"[idb-repl] generated .swiftinterface under: %s", generated);
      free((void *)generated);
    } else {
      NSLog(@"[idb-repl] runtime probe produced no .swiftinterface output");
    }
  }

  // Start the shared ReplExecutor with the requested socket path.
  NSString *socketPath = environment[@"IDB_REPL_SOCKET_PATH"];
  FBReplServeSocket(socketPath);
}

@end
