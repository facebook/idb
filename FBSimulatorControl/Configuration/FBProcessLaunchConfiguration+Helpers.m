/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessLaunchConfiguration+Helpers.h"

#import "FBProcessLaunchConfiguration+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorError.h"

@implementation FBProcessLaunchConfiguration (Helpers)

- (instancetype)withEnvironmentAdditions:(NSDictionary *)environmentAdditions
{
  NSMutableDictionary *environment = [[self environment] mutableCopy];
  [environment addEntriesFromDictionary:environmentAdditions];

  FBProcessLaunchConfiguration *configuration = [self copy];
  configuration.environment = [environment copy];
  return configuration;
}

- (instancetype)withDiagnosticEnvironment
{
  // It looks like DYLD_PRINT is not currently working as per TN2239.
  return [self withEnvironmentAdditions:@{
    @"OBJC_PRINT_LOAD_METHODS" : @"YES",
    @"OBJC_PRINT_IMAGES" : @"YES",
    @"OBJC_PRINT_IMAGE_TIMES" : @"YES",
    @"DYLD_PRINT_STATISTICS" : @"1",
    @"DYLD_PRINT_ENV" : @"1",
    @"DYLD_PRINT_LIBRARIES" : @"1"
  }];
}

- (instancetype)injectingLibrary:(NSString *)filePath
{
  NSParameterAssert(filePath);

  return [self withEnvironmentAdditions:@{
    @"DYLD_INSERT_LIBRARIES" : filePath
  }];
}

- (instancetype)injectingShimulator
{
  return [self injectingLibrary:[[NSBundle bundleForClass:self.class] pathForResource:@"libShimulator" ofType:@"dylib"]];
}

- (BOOL)createFileHandlesWithStdOut:(NSFileHandle **)stdOut stdErr:(NSFileHandle **)stdErr error:(NSError **)error
{
  if (self.stdOutPath) {
    if (![NSFileManager.defaultManager createFileAtPath:self.stdOutPath contents:NSData.data attributes:nil]) {
      return [[FBSimulatorError describeFormat:
        @"Could not create stdout at path '%@' for config '%@'",
        self.stdOutPath,
        self
      ] failBool:error];
    }
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.stdOutPath];
    if (!fileHandle) {
      return [[FBSimulatorError describeFormat:
        @"Could not file handle for stdout at path '%@' for config '%@'",
        self.stdOutPath,
        self
      ] failBool:error];
    }
    *stdOut = fileHandle;
  }
  if (self.stdErrPath) {
    if (![NSFileManager.defaultManager createFileAtPath:self.stdErrPath contents:NSData.data attributes:nil]) {
      return [[FBSimulatorError describeFormat:
      @"Could not create stderr at path '%@' for config '%@'",
      self.stdErrPath,
      self
      ] failBool:error];
    }
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.stdErrPath];
    if (!fileHandle) {
      return [[FBSimulatorError describeFormat:
        @"Could not file handle for stderr at path '%@' for config '%@'",
        self.stdErrPath,
        self
      ] failBool:error];
    }
    *stdErr = fileHandle;
  }
  return YES;
}

- (NSDictionary *)agentLaunchOptionsWithStdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr error:(NSError **)error
{
  NSMutableDictionary *options = [@{
    @"arguments" : self.arguments,
    // iOS 7 Launch fails if the environment is empty, put some nothing in the environment for it.
    @"environment" : self.environment.count ? self.environment:  @{@"__SOME_MAGIC__" : @"__IS_ALIVE__"}
  } mutableCopy];

  if (stdOut){
    options[@"stdout"] = @([stdOut fileDescriptor]);
  }
  if (stdErr) {
    options[@"stderr"] = @([stdErr fileDescriptor]);
  }
  return [options copy];
}

@end
