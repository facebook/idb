/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessStream.h"

#import <sys/types.h>
#import <sys/stat.h>

#pragma mark FBProcessFileOutput

@interface FBProcessFileOutput_DirectToFile : NSObject <FBProcessFileOutput>

@end

@interface FBProcessFileOutput_Consumer : NSObject <FBProcessFileOutput>

@property (nonatomic, strong, readonly) id<FBFileConsumer> consumer;
@property (nonatomic, strong, nullable, readwrite) FBFileReader *reader;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@interface FBProcessFileOutput_Reader : NSObject <FBProcessFileOutput>

@property (nonatomic, strong, readonly) FBProcessOutput *output;
@property (nonatomic, strong, nullable, readwrite) FBFileWriter *writer;
@property (nonatomic, strong, nullable, readwrite) id<FBProcessFileOutput> nested;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBProcessFileOutput_DirectToFile

@synthesize filePath = _filePath;

- (instancetype)initWithFilePath:(NSString *)filePath
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _filePath = filePath;

  return self;
}

- (FBFuture<NSNull *> *)startReading
{
  return [FBFuture futureWithResult:NSNull.null];
}

- (FBFuture<NSNull *> *)stopReading
{
  return [FBFuture futureWithResult:NSNull.null];
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Output to %@", self.filePath];
}

@end

@implementation FBProcessFileOutput_Consumer

@synthesize filePath = _filePath;

- (instancetype)initWithConsumer:(id<FBFileConsumer>)consumer filePath:(NSString *)filePath queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;
  _filePath = filePath;
  _queue = queue;

  return self;
}

- (FBFuture<NSNull *> *)startReading
{
  return [[[FBFuture
    onQueue:self.queue resolve:^ FBFuture<FBFileReader *> * {
      if (self.reader) {
        return [[FBControlCoreError
          describeFormat:@"Cannot call startReading twice"]
          failFuture];
      }
      return [FBFileReader readerWithFilePath:self.filePath consumer:self.consumer];
    }]
    onQueue:self.queue fmap:^(FBFileReader *reader) {
      return [[reader startReading] mapReplace:reader];
    }]
    onQueue:self.queue map:^(FBFileReader *reader) {
      self.reader = reader;
      return NSNull.null;
    }];
}

- (FBFuture<NSNull *> *)stopReading
{
  return [[FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSNull *> * {
      if (!self.reader) {
      return [[FBControlCoreError
        describeFormat:@"No active reader for fifo"]
        failFuture];
      }
      return [self.reader stopReading];
    }]
    onQueue:self.queue map:^(id _) {
      self.reader = nil;
      return NSNull.null;
    }];
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Output to %@", self.filePath];
}

@end

@implementation FBProcessFileOutput_Reader

@synthesize filePath = _filePath;

- (instancetype)initWithOutput:(FBProcessOutput *)output filePath:(NSString *)filePath queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _output = output;
  _filePath = filePath;
  _queue = queue;

  return self;
}

- (FBFuture<NSNull *> *)startReading
{
  return [[[[FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSFileHandle *> * {
      if (self.writer || self.nested) {
        return [[FBControlCoreError
          describe:@"Cannot call startReading twice"]
          failFuture];
      }
      return [self.output attachToFileHandle];
    }]
    onQueue:self.queue map:^ FBFileWriter * (NSFileHandle *fileHandle) {
      return [FBFileWriter syncWriterWithFileHandle:fileHandle];
    }]
    onQueue:self.queue fmap:^ FBFuture<id<FBProcessFileOutput>> * (FBFileWriter *writer) {
      self.writer = writer;
      id<FBProcessFileOutput> consumer = [[FBProcessFileOutput_Consumer alloc] initWithConsumer:writer filePath:self.filePath queue:self.queue];
      return [[consumer startReading] mapReplace:consumer];
    }]
    onQueue:self.queue map:^ NSNull * (id<FBProcessFileOutput> nested) {
      self.nested = nested;
      return NSNull.null;
    }];
}

- (FBFuture<NSNull *> *)stopReading
{
  return [[FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSNull *> * {
      if (!self.writer || !self.nested) {
        return [[FBControlCoreError
          describeFormat:@"No active reader for fifo"]
          failFuture];
      }
      return [self.nested stopReading];
    }]
    onQueue:self.queue map:^(id _) {
      self.nested = nil;
      return NSNull.null;
    }];
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Output of %@ to file handle", self.filePath];
}

@end

#pragma mark FBProcessOutput

FBiOSTargetFutureType const FBiOSTargetFutureTypeProcessOutput = @"process_output";

@interface FBProcessOutput ()

@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;

@end

@interface FBProcessOutput_Null : FBProcessOutput

@end

@interface FBProcessOutput_FileHandle : FBProcessOutput

@property (nonatomic, strong, nullable, readwrite) FBDiagnostic *diagnostic;
@property (nonatomic, strong, nullable, readwrite) NSFileHandle *fileHandle;

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle diagnostic:(FBDiagnostic *)diagnostic;

@end

@interface FBProcessOutput_FilePath : FBProcessOutput

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

@property (nonatomic, strong, readonly) id<FBAccumulatingLineBuffer> dataConsumer;

- (instancetype)initWithMutableData:(NSMutableData *)mutableData;

@end

@interface FBProcessOutput_String : FBProcessOutput_Data

@end

@interface FBProcessInput ()

@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;
@property (nonatomic, strong, nullable, readwrite) NSPipe *pipe;
@property (nonatomic, strong, nullable, readwrite) id<FBFileConsumer> writer;

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
  return [[FBProcessOutput_Null alloc] init];
}

+ (FBProcessOutput<NSString *> *)outputForFilePath:(NSString *)filePath
{
  return [[FBProcessOutput_FilePath alloc] initWithFilePath:filePath];
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

- (instancetype)init
{
  return [self initWithWorkQueue:FBProcessOutput.createWorkQueue];
}

- (instancetype)initWithWorkQueue:(dispatch_queue_t)workQueue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _workQueue = workQueue;

  return self;
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

- (FBFuture<id<FBProcessFileOutput>> *)providedThroughFile
{
  return [[self
    makeFifoOutput]
    onQueue:self.workQueue map:^(NSString *fifoPath) {
      return [[FBProcessFileOutput_Reader alloc] initWithOutput:self filePath:fifoPath queue:FBProcessOutput.createWorkQueue];
    }];
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

#pragma mark Private

- (FBFuture<NSString *> *)makeFifoOutput
{
  NSString *fifoPath = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  if (mkfifo(fifoPath.UTF8String, S_IWUSR | S_IRUSR) != 0) {
    return [[[[FBControlCoreError
      describeFormat:@"Failed to create a named pipe %@", fifoPath]
      code:errno]
      inDomain:NSPOSIXErrorDomain]
      failFuture];
  }
  return [FBFuture futureWithResult:fifoPath];
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

@implementation FBProcessOutput_Null

#pragma mark FBStandardStream

- (FBFuture<NSFileHandle *> *)attachToFileHandle
{
  return [FBFuture futureWithResult:NSFileHandle.fileHandleWithNullDevice];
}

- (FBFuture<NSFileHandle *> *)attachToPipeOrFileHandle
{
  return [self attachToFileHandle];
}

- (FBFuture<id<FBProcessFileOutput>> *)providedThroughFile
{
  return [FBFuture futureWithResult:[[FBProcessFileOutput_DirectToFile alloc] initWithFilePath:@"/dev/null"]];
}

- (FBFuture<NSNull *> *)detach
{
  return [FBFuture futureWithResult:NSNull.null];
}

- (NSNull *)contents
{
  return NSNull.null;
}

#pragma mark FBiOSTargetContinuation

- (FBFuture<NSNull *> *)completed
{
  return [FBFuture futureWithResult:NSNull.null];
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
  return [FBFuture onQueue:self.workQueue resolve:^{
    NSFileHandle *fileHandle = self.fileHandle;
    if (!fileHandle) {
      return [[FBControlCoreError
        describe:@"Cannot detach, there is no file handle"]
        failFuture];
    }

    self.fileHandle = nil;
    [fileHandle closeFile];
    return [FBFuture futureWithResult:NSNull.null];
  }];
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
    onQueue:self.workQueue respondToCancellation:^{
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
    onQueue:self.workQueue map:^(NSPipe *pipe) {
      return pipe.fileHandleForWriting;
    }];
}

- (FBFuture<NSPipe *> *)attachToPipeOrFileHandle
{
  return [FBFuture onQueue:self.workQueue resolve:^{
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
  }];
}

- (FBFuture<id<FBProcessFileOutput>> *)providedThroughFile
{
  return [[self
    makeFifoOutput]
    onQueue:self.workQueue map:^ id<FBProcessFileOutput> (NSString *fifoPath) {
      return [[FBProcessFileOutput_Consumer alloc] initWithConsumer:self.consumer filePath:fifoPath queue:FBProcessOutput.createWorkQueue];
    }];
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
    onQueue:self.workQueue chain:^(FBFuture *future) {
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

@implementation FBProcessOutput_FilePath

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
  return [FBFuture onQueue:self.workQueue resolve:^{
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
  }];
}

- (FBFuture<NSFileHandle *> *)attachToPipeOrFileHandle
{
  return [self attachToFileHandle];
}

- (FBFuture<NSNull *> *)detach
{
  return [FBFuture onQueue:self.workQueue resolve:^{
    NSFileHandle *fileHandle = self.fileHandle;
    if (!fileHandle) {
      return [[FBControlCoreError
        describe:@"Cannot Detach Twice"]
        failFuture];
    }
    self.fileHandle = nil;
    [fileHandle closeFile];
    return [FBFuture futureWithResult:NSNull.null];
  }];
}

- (FBFuture<id<FBProcessFileOutput>> *)providedThroughFile
{
  return [FBFuture futureWithResult:[[FBProcessFileOutput_DirectToFile alloc] initWithFilePath:self.filePath]];
}

- (NSString *)contents
{
  return self.filePath;
}

@end

@implementation FBProcessOutput_Data

- (instancetype)initWithMutableData:(NSMutableData *)mutableData
{
  id<FBAccumulatingLineBuffer> consumer = [FBLineBuffer accumulatingBufferForMutableData:mutableData];
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

- (instancetype)init
{
  return [self initWithWorkQueue:FBProcessOutput.createWorkQueue];
}

- (instancetype)initWithWorkQueue:(dispatch_queue_t)workQueue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _workQueue = workQueue;

  return self;
}

#pragma mark FBStandardStream

- (FBFuture<NSFileHandle *> *)attachToFileHandle
{
  return [[self
    attachToPipeOrFileHandle]
    onQueue:self.workQueue map:^(NSPipe *pipe) {
      return pipe.fileHandleForReading;
    }];
}

- (FBFuture<NSPipe *> *)attachToPipeOrFileHandle
{
  return [FBFuture onQueue:self.workQueue resolve:^{
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
    self.pipe = pipe;
    self.writer = writer;
    return [FBFuture futureWithResult:pipe];
  }];
}

- (FBFuture<NSNull *> *)detach
{
  return [FBFuture onQueue:self.workQueue resolve:^{
    NSPipe *pipe = self.pipe;
    id<FBFileConsumer> consumer = self.writer;
    if (!pipe || !consumer) {
      return [[FBControlCoreError
        describeFormat:@"Nothing is attached to %@", self]
        failFuture];
    }

    [pipe.fileHandleForWriting closeFile];
    self.pipe = nil;
    self.writer = nil;

    return [FBFuture futureWithResult:NSNull.null];
  }];
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
    onQueue:self.workQueue map:^(NSPipe *pipe) {
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
