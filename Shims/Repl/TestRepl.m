/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "TestRepl.h"

#import <ReplExecutor/ReplSocketServer.h>

// Walks the target image's Swift metadata and writes <Module>.swiftinterface
// file(s); returns the written paths joined by newlines in a malloc'd string
// the caller must free, or NULL.
extern const char *FBReplGenerateSwiftInterface(const char *outDir, const char *imageFilter);

@implementation TestRepl

- (void)start
{
  NSDictionary<NSString *, NSString *> *environment = [[NSProcessInfo processInfo] environment];

  NSArray<NSString *> *generatedInterfaces = @[];
  NSString *interfaceDir = environment[@"IDB_REPL_GEN_INTERFACE_DIR"];
  if (interfaceDir.length > 0) {
    NSString *imageFilter = environment[@"IDB_REPL_PROBE_IMAGE"] ?: @"";
    const char *generated =
    FBReplGenerateSwiftInterface(interfaceDir.fileSystemRepresentation, imageFilter.UTF8String);
    if (generated) {
      generatedInterfaces = [@(generated) componentsSeparatedByString:@"\n"];
      free((void *)generated);
    } else {
      NSLog(@"[idb-repl] runtime probe produced no .swiftinterface output");
    }
  }

  // Start the shared ReplExecutor with the requested socket path.
  NSString *socketPath = environment[@"IDB_REPL_SOCKET_PATH"];
  FBReplServeSocket(socketPath, generatedInterfaces);
}

@end
