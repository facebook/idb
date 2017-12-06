/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessOutput.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeProcessOutput = @"process_output";

@interface FBProcessOutput_FileHandle : FBProcessOutput

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle diagnostic:(FBDiagnostic *)diagnostic;

@end

@interface FBProcessOutput_Consumer : FBProcessOutput

@property (nonatomic, strong, readonly) FBPipeReader *reader;

- (instancetype)initWithReader:(FBPipeReader *)reader;

@end

@implementation FBProcessOutput

#pragma mark Initializers

+ (instancetype)outputForFileHandle:(NSFileHandle *)fileHandle diagnostic:(FBDiagnostic *)diagnostic
{
  return [[FBProcessOutput_FileHandle alloc] initWithFileHandle:fileHandle diagnostic:diagnostic];
}

+ (FBFuture<FBProcessOutput *> *)outputWithConsumer:(id<FBFileConsumer>)consumer
{
  FBPipeReader *reader = [FBPipeReader pipeReaderWithConsumer:consumer];
  return [[reader
    startReading]
    onQueue:dispatch_get_main_queue() map:^(id _) {
      return [[FBProcessOutput_Consumer alloc] initWithReader:reader];
    }];
}

#pragma mark Public Properties

- (NSFileHandle *)fileHandle
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBDiagnostic *)diagnostic
{
  return nil;
}

#pragma mark FBiOSTargetContinuation

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeProcessOutput;
}

- (FBFuture<NSNull *> *)completed
{
  return nil;
}

@end

@implementation FBProcessOutput_FileHandle

@synthesize diagnostic = _diagnostic;
@synthesize fileHandle = _fileHandle;

#pragma mark Initializers

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

#pragma mark FBiOSTargetContinuation

- (FBFuture<NSNull *> *)completed
{
  NSFileHandle *fileHandle = self.fileHandle;
  return [[FBFuture
    futureWithResult:NSNull.null]
    onQueue:dispatch_get_main_queue() respondToCancellation:^{
      [fileHandle closeFile];
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

@end

@implementation FBProcessOutput_Consumer

#pragma mark Initializers

- (instancetype)initWithReader:(FBPipeReader *)reader
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _reader = reader;

  return self;
}

#pragma mark Public Properties

- (NSFileHandle *)fileHandle
{
  return self.reader.pipe.fileHandleForWriting;
}

#pragma mark FBiOSTargetContinuation

- (FBFuture<NSNull *> *)completed
{
  FBPipeReader *reader = self.reader;
  return [[FBFuture
    futureWithResult:NSNull.null]
    onQueue:dispatch_get_main_queue() respondToCancellation:^{
      return [reader stopReading];
    }];
}

@end
