/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessStream.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeProcessOutput = @"process_output";

@interface FBProcessOutput_FileHandle : FBProcessOutput

@property (nonatomic, strong, nullable, readwrite) FBDiagnostic *diagnostic;
@property (nonatomic, strong, nullable, readwrite) NSFileHandle *fileHandle;

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle diagnostic:(FBDiagnostic *)diagnostic;

@end

@interface FBProcessOutput_File : FBProcessOutput

@property (nonatomic, copy, nullable, readonly) NSString *filePath;
@property (nonatomic, strong, nullable, readwrite) NSFileHandle *fileHandle;

- (instancetype)initWithFilePath:(NSString *)filePath;

@end

@interface FBProcessOutput_Consumer : FBProcessOutput

@property (nonatomic, strong, nullable, readwrite) NSPipe *pipe;
@property (nonatomic, strong, nullable, readwrite) FBFileReader *reader;
@property (nonatomic, strong, nullable, readwrite) id<FBFileConsumer> consumer;

- (instancetype)initWithConsumer:(id<FBFileConsumer>)consumer;

@end

@interface FBProcessOutput_Logger : FBProcessOutput_Consumer

@property (nonatomic, strong, readwrite) id<FBControlCoreLogger> logger;

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger;

@end

@interface FBProcessOutput_Data : FBProcessOutput_Consumer

@property (nonatomic, strong, readonly) FBAccumilatingFileConsumer *dataConsumer;

- (instancetype)initWithMutableData:(NSMutableData *)mutableData;

@end

@interface FBProcessOutput_String : FBProcessOutput_Data

@end

@interface FBProcessInput ()

@property (nonatomic, strong, nullable, readonly) NSPipe *pipe;
@property (nonatomic, strong, nullable, readonly) id<FBFileConsumer> writer;

@end

@interface FBProcessInput_Consumer : FBProcessInput <FBFileConsumer>

@end

@interface FBProcessInput_Data : FBProcessInput

- (instancetype)initWithData:(NSData *)data;

@property (nonatomic, strong, readonly) NSData *data;

@end

@implementation FBProcessOutput

#pragma mark Initializers

+ (dispatch_queue_t)createWorkQueue
{
  return dispatch_queue_create("com.facebook.fbcontrolcore.process_stream", DISPATCH_QUEUE_SERIAL);
}

+ (FBProcessOutput<NSNull *> *)outputForNullDevice
{
  return [[FBProcessOutput_FileHandle alloc] initWithFileHandle:NSFileHandle.fileHandleWithNullDevice diagnostic:nil];
}

+ (FBProcessOutput<NSFileHandle *> *)outputForFileHandle:(NSFileHandle *)fileHandle diagnostic:(FBDiagnostic *)diagnostic
{
  return [[FBProcessOutput_FileHandle alloc] initWithFileHandle:fileHandle diagnostic:diagnostic];
}

+ (FBProcessOutput<NSString *> *)outputForFilePath:(NSString *)filePath
{
  return [[FBProcessOutput_File alloc] initWithFilePath:filePath];
}

+ (FBProcessOutput<id<FBFileConsumer>> *)outputForFileConsumer:(id<FBFileConsumer>)fileConsumer
{
  return [[FBProcessOutput_Consumer alloc] initWithConsumer:fileConsumer];
}

+ (FBProcessOutput<id<FBControlCoreLogger>> *)outputForLogger:(id<FBControlCoreLogger>)logger
{
  return [[FBProcessOutput_Logger alloc] initWithLogger:logger];
}

+ (FBProcessOutput<NSMutableData *> *)outputToMutableData:(NSMutableData *)data
{
  return [[FBProcessOutput_Data alloc] initWithMutableData:data];
}

+ (FBProcessOutput<NSString *> *)outputToStringBackedByMutableData:(NSMutableData *)data
{
  return [[FBProcessOutput_String alloc] initWithMutableData:data];
}

#pragma mark FBStandardStream

- (FBFuture<NSFileHandle *> *)attachToFileHandle
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBFuture<id> *)attachToPipeOrFileHandle
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBFuture<NSNull *> *)detach
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBDiagnostic *)contents
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
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

#pragma mark FBStandardStream

- (FBFuture<NSFileHandle *> *)attachToFileHandle
{
  return [FBFuture futureWithResult:self.fileHandle];
}

- (FBFuture<NSFileHandle *> *)attachToPipeOrFileHandle
{
  return [self attachToFileHandle];
}

- (FBFuture<NSNull *> *)detach
{
  NSFileHandle *fileHandle = self.fileHandle;
  if (!fileHandle) {
    return [[FBControlCoreError
      describe:@"Cannot detach, there is no file handle"]
      failFuture];
  }

  self.fileHandle = nil;
  [fileHandle closeFile];
  return [FBFuture futureWithResult:NSNull.null];
}

- (FBDiagnostic *)contents
{
  return self.diagnostic;
}

#pragma mark FBiOSTargetContinuation

- (FBFuture<NSNull *> *)completed
{
  return [[FBFuture
    futureWithResult:NSNull.null]
    onQueue:FBProcessOutput.createWorkQueue respondToCancellation:^{
      return [self detach];
    }];
}

@end

@implementation FBProcessOutput_Consumer

#pragma mark Initializers

- (instancetype)initWithConsumer:(id<FBFileConsumer>)consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;

  return self;
}

#pragma mark FBStandardStream

- (FBFuture<NSFileHandle *> *)attachToFileHandle
{
  return [[self
    attachToPipeOrFileHandle]
    onQueue:FBProcessOutput.createWorkQueue map:^(NSPipe *pipe) {
      return pipe.fileHandleForWriting;
    }];
}

- (FBFuture<NSPipe *> *)attachToPipeOrFileHandle
{
  if (self.pipe) {
    return [[FBControlCoreError
      describeFormat:@"Cannot attach when already attached to %@", self.reader]
      failFuture];
  }

  self.pipe = NSPipe.pipe;
  self.reader = [FBFileReader readerWithFileHandle:self.pipe.fileHandleForReading consumer:self.consumer];
  return [[self.reader
    startReading]
    mapReplace:self.pipe];
}

- (id<FBFileConsumer>)contents
{
  return self.consumer;
}

#pragma mark FBiOSTargetContinuation

- (FBFuture<NSNull *> *)completed
{
  return self.reader.completed;
}

- (FBFuture<NSNull *> *)detach
{
  return [self.reader.stopReading
    onQueue:FBProcessOutput.createWorkQueue chain:^(FBFuture *future) {
      NSPipe *pipe = self.pipe;
      [pipe.fileHandleForWriting closeFile];

      self.reader = nil;
      self.pipe = nil;
      return future;
    }];
}

@end

@implementation FBProcessOutput_Logger

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger
{
  id<FBFileConsumer> consumer = [FBLoggingFileConsumer consumerWithLogger:logger];
  self = [super initWithConsumer:consumer];
  if (!self) {
    return nil;
  }

  _logger = logger;

  return self;
}

- (id<FBControlCoreLogger>)contents
{
  return self.logger;
}

@end

@implementation FBProcessOutput_File

- (instancetype)initWithFilePath:(NSString *)filePath
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _filePath = filePath;

  return self;
}

#pragma mark FBStandardStream

- (FBFuture<NSFileHandle *> *)attachToFileHandle
{
  if (self.fileHandle) {
    return [[FBControlCoreError
      describeFormat:@"Cannot attach when already attached to file %@", self.fileHandle]
      failFuture];
  }

  if (!self.filePath) {
    self.fileHandle = NSFileHandle.fileHandleWithNullDevice;
    return [FBFuture futureWithResult:self.fileHandle];
  }

  if (![NSFileManager.defaultManager createFileAtPath:self.filePath contents:nil attributes:nil]) {
    return [[FBControlCoreError
      describeFormat:@"Could not create file for writing at %@", self.filePath]
      failFuture];
  }
  self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.filePath];
  return [FBFuture futureWithResult:self.fileHandle];
}

- (FBFuture<NSFileHandle *> *)attachToPipeOrFileHandle
{
  return [self attachToFileHandle];
}

- (FBFuture<NSNull *> *)detach
{
  NSFileHandle *fileHandle = self.fileHandle;
  if (!fileHandle) {
    return [[FBControlCoreError
      describe:@"Cannot Detach Twice"]
      failFuture];
  }
  self.fileHandle = nil;
  [fileHandle closeFile];
  return [FBFuture futureWithResult:NSNull.null];
}

- (NSString *)contents
{
  return self.filePath;
}

@end

@implementation FBProcessOutput_Data

- (instancetype)initWithMutableData:(NSMutableData *)mutableData
{
  FBAccumilatingFileConsumer *consumer = [[FBAccumilatingFileConsumer alloc] initWithMutableData:mutableData];
  self = [super initWithConsumer:consumer];
  if (!self) {
    return nil;
  }

  _dataConsumer = consumer;

  return self;
}

- (NSData *)contents
{
  return self.dataConsumer.data;
}

@end

@implementation FBProcessOutput_String

- (NSString *)contents
{
  NSData *data = self.dataConsumer.data;
  // Strip newline from the end of the buffer.
  if (data.length) {
    char lastByte = 0;
    NSRange range = NSMakeRange(data.length - 1, 1);
    [data getBytes:&lastByte range:range];
    if (lastByte == '\n') {
      data = [data subdataWithRange:NSMakeRange(0, data.length - 1)];
    }
  }
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end

@implementation FBProcessInput

#pragma mark Initializers

+ (FBProcessInput<id<FBFileConsumer>> *)inputProducingConsumer
{
  return [[FBProcessInput_Consumer alloc] init];
}

+ (FBProcessInput<NSData *> *)inputFromData:(NSData *)data
{
  return [[FBProcessInput_Data alloc] initWithData:data];
}

#pragma mark FBStandardStream

- (FBFuture<NSFileHandle *> *)attachToFileHandle
{
  return [[self
    attachToPipeOrFileHandle]
    onQueue:FBProcessOutput.createWorkQueue map:^(NSPipe *pipe) {
      return pipe.fileHandleForReading;
    }];
}

- (FBFuture<NSPipe *> *)attachToPipeOrFileHandle
{
  if (self.pipe || self.writer) {
    return [[FBControlCoreError
      describeFormat:@"Cannot Attach Twice"]
      failFuture];
  }

  NSPipe *pipe = NSPipe.pipe;
  NSError *error = nil;
  id<FBFileConsumer> writer = [FBFileWriter asyncWriterWithFileHandle:pipe.fileHandleForWriting error:&error];
  if (!writer) {
    return [[FBControlCoreError
      describeFormat:@"Failed to create a writer for pipe %@", error]
      failFuture];
  }
  _pipe = pipe;
  _writer = writer;
  return [FBFuture futureWithResult:pipe];
}

- (FBFuture<NSNull *> *)detach
{
  NSPipe *pipe = self.pipe;
  id<FBFileConsumer> consumer = self.writer;
  if (!pipe || !consumer) {
    return [[FBControlCoreError
      describeFormat:@"Nothing is attached to %@", self]
      failFuture];
  }

  [pipe.fileHandleForWriting closeFile];
  _pipe = nil;
  _writer = nil;

  return [FBFuture futureWithResult:NSNull.null];
}

- (id<FBFileConsumer>)contents
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@implementation FBProcessInput_Consumer

#pragma mark FBStandardStream

- (void)consumeData:(NSData *)data
{
  [self.writer consumeData:data];
}

- (void)consumeEndOfFile
{
  [self.writer consumeEndOfFile];
  [self detach];
}

- (id<FBFileConsumer>)contents
{
  return self;
}

@end

@implementation FBProcessInput_Data

- (instancetype)initWithData:(NSData *)data
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _data = data;

  return self;
}

#pragma mark FBStandardStream

- (FBFuture<NSPipe *> *)attachToPipeOrFileHandle
{
  return [[super
    attachToPipeOrFileHandle]
    onQueue:FBProcessOutput.createWorkQueue map:^(NSPipe *pipe) {
      [self.writer consumeData:self.data];
      [self.writer consumeEndOfFile];
      return pipe;
    }];
}

- (NSData *)contents
{
  return self.data;
}

@end
