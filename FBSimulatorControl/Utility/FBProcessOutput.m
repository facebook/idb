/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessOutput.h"

FBTerminationHandleType const FBTerminationHandleTypeProcessOutput = @"process_output";

@implementation FBProcessOutput

+ (instancetype)outputForFileHandle:(NSFileHandle *)fileHandle diagnostic:(FBDiagnostic *)diagnostic
{
  return [[self alloc] initWithFileHandle:fileHandle diagnostic:diagnostic];
}

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle diagnostic:(FBDiagnostic *)diagnostic
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileHandle = fileHandle;
  _diagnostic = diagnostic;

  return self;
}

#pragma mark FBTerminationHandle

- (void)terminate
{
  [self.fileHandle closeFile];
}

+ (FBTerminationHandleType)handleType
{
  return FBTerminationHandleTypeProcessOutput;
}

@end
