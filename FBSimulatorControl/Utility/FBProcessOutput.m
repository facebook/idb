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

+ (nullable instancetype)outputWithConsumer:(id<FBFileConsumer>)consumer error:(NSError **)error
{
  FBPipeReader *reader = [FBPipeReader pipeReaderWithConsumer:consumer];
  if (![reader startReadingWithError:error]) {
    return nil;
  }
  return [[FBProcessOutput_Consumer alloc] initWithReader:reader];
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

#pragma mark FBTerminationHandle

- (void)terminate
{
}

- (FBTerminationHandleType)handleType
{
  return FBTerminationHandleTypeProcessOutput;
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

#pragma mark Public Properties


#pragma mark FBTerminationHandle

- (void)terminate
{
  [self.fileHandle closeFile];
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

#pragma mark FBTerminationHandle

- (void)terminate
{
  [self.reader stopReadingWithError:nil];
}

@end
