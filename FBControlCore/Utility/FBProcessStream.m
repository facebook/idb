/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessStream.h"

#import <sys/types.h>
#import <sys/stat.h>

#import "FBControlCoreError.h"
#import "FBDataBuffer.h"
#import "FBFileReader.h"
#import "FBFileWriter.h"

static NSTimeInterval ProcessDetachDrainTimeout = 4;

#pragma mark FBProcessFileOutput

@interface FBProcessFileOutput_DirectToFile : NSObject <FBProcessFileOutput>

@end

@interface FBProcessFileOutput_Consumer : NSObject <FBProcessFileOutput>

@property (nonatomic, strong, readonly) id<FBDataConsumer> consumer;
@property (nonatomic, strong, nullable, readwrite) FBFileReader *reader;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@interface FBProcessFileOutput_Reader : NSObject <FBProcessFileOutput>

@property (nonatomic, strong, readonly) FBProcessOutput *output;
@property (nonatomic, strong, nullable, readwrite) id<FBDataConsumer> writer;
@property (nonatomic, strong, nullable, readwrite) id<FBProcessFileOutput> nested;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBProcessFileOutput_DirectToFile

@synthesize filePath = _filePath;

#pragma mark Initializers

- (instancetype)initWithFilePath:(NSString *)filePath
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _filePath = filePath;

  return self;
}

#pragma mark FBProcessFileOutput

- (FBFuture<NSNull *> *)startReading
{
  return [[FBFuture
    futureWithResult:NSNull.null]
    nameFormat:@"Start reading %@", self.description];
}

- (FBFuture<NSNull *> *)stopReading
{
  return [[FBFuture
    futureWithResult:NSNull.null]
    nameFormat:@"Stop reading %@", self.description];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"File output to %@", self.filePath];
}

@end

@implementation FBProcessFileOutput_Consumer

@synthesize filePath = _filePath;

#pragma mark Initializers

- (instancetype)initWithConsumer:(id<FBDataConsumer>)consumer filePath:(NSString *)filePath queue:(dispatch_queue_t)queue
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

#pragma mark FBProcessFileOutput

- (FBFuture<NSNull *> *)startReading
{
  return [[[[FBFuture
    onQueue:self.queue resolve:^ FBFuture<FBFileReader *> * {
      if (self.reader) {
        return [[FBControlCoreError
          describeFormat:@"Cannot call startReading twice"]
          failFuture];
      }
      return [FBFileReader readerWithFilePath:self.filePath consumer:self.consumer logger:nil];
    }]
    onQueue:self.queue fmap:^(FBFileReader *reader) {
      return [[reader startReading] mapReplace:reader];
    }]
    onQueue:self.queue map:^(FBFileReader *reader) {
      self.reader = reader;
      return NSNull.null;
    }]
    nameFormat:@"Start reading %@", self.description];
}

- (FBFuture<NSNull *> *)stopReading
{
  return [[[FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSNumber *> * {
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
    }]
    nameFormat:@"Stop reading %@", self.description];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Consumer output to %@", self.filePath];
}

@end

@implementation FBProcessFileOutput_Reader

@synthesize filePath = _filePath;

#pragma mark Initializers

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

#pragma mark FBProcessFileOutput

- (FBFuture<NSNull *> *)startReading
{
  return [[[[[FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSFileHandle *> * {
      if (self.writer || self.nested) {
        return [[FBControlCoreError
          describe:@"Cannot call startReading twice"]
          failFuture];
      }
      return [self.output attachToFileHandle];
    }]
    onQueue:self.queue map:^ id<FBDataConsumer>  (NSFileHandle *fileHandle) {
      return [FBFileWriter syncWriterWithFileHandle:fileHandle];
    }]
    onQueue:self.queue fmap:^ FBFuture<id<FBProcessFileOutput>> * (id<FBDataConsumer> writer) {
      self.writer = writer;
      id<FBProcessFileOutput> consumer = [[FBProcessFileOutput_Consumer alloc] initWithConsumer:writer filePath:self.filePath queue:self.queue];
      return [[consumer startReading] mapReplace:consumer];
    }]
    onQueue:self.queue map:^ NSNull * (id<FBProcessFileOutput> nested) {
      self.nested = nested;
      return NSNull.null;
    }]
    nameFormat:@"Start Reading %@", self.description];
}

- (FBFuture<NSNull *> *)stopReading
{
  return [[[FBFuture
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
    }]
    nameFormat:@"Stop Reading %@", self.description];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Output of %@ to file handle", self.filePath];
}

@end

#pragma mark - FBProcessOutput

FBiOSTargetFutureType const FBiOSTargetFutureTypeProcessOutput = @"process_output";

@interface FBProcessOutput ()

@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;

@end

@interface FBProcessOutput_Null : FBProcessOutput

@end

@interface FBProcessOutput_FilePath : FBProcessOutput

@property (nonatomic, copy, nullable, readonly) NSString *filePath;
@property (nonatomic, strong, nullable, readwrite) NSFileHandle *fileHandle;

- (instancetype)initWithFilePath:(NSString *)filePath;

@end

@interface FBProcessOutput_Consumer : FBProcessOutput

@property (nonatomic, strong, nullable, readwrite) NSPipe *pipe;
@property (nonatomic, strong, nullable, readwrite) FBFileReader *reader;
@property (nonatomic, strong, nullable, readwrite) id<FBDataConsumer> consumer;
@property (nonatomic, strong, nullable, readwrite) id<FBControlCoreLogger> logger;

- (instancetype)initWithConsumer:(id<FBDataConsumer>)consumer logger:(nullable id<FBControlCoreLogger>)logger;

@end

@interface FBProcessOutput_Logger : FBProcessOutput_Consumer

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger;

@end

@interface FBProcessOutput_Data : FBProcessOutput_Consumer

@property (nonatomic, strong, readonly) id<FBAccumulatingBuffer> dataConsumer;

- (instancetype)initWithMutableData:(NSMutableData *)mutableData;

@end

@interface FBProcessOutput_String : FBProcessOutput_Data

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

+ (FBProcessOutput<id<FBDataConsumer>> *)outputForDataConsumer:(id<FBDataConsumer>)dataConsumer logger:(nullable id<FBControlCoreLogger>)logger
{
  return [[FBProcessOutput_Consumer alloc] initWithConsumer:dataConsumer logger:logger];
}

+ (FBProcessOutput<id<FBDataConsumer>> *)outputForDataConsumer:(id<FBDataConsumer>)dataConsumer
{
  return [[FBProcessOutput_Consumer alloc] initWithConsumer:dataConsumer logger:nil];
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

- (FBFuture<NSNull *> *)detach
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (id)contents
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark FBProcessOutput implementation

- (FBFuture<id<FBProcessFileOutput>> *)providedThroughFile
{
  return [[self
    makeFifoOutput]
    onQueue:self.workQueue map:^(NSString *fifoPath) {
      return [[FBProcessFileOutput_Reader alloc] initWithOutput:self filePath:fifoPath queue:FBProcessOutput.createWorkQueue];
    }];
}

- (FBFuture<id<FBDataConsumer>> *)providedThroughConsumer
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark Private

- (FBFuture<NSString *> *)makeFifoOutput
{
  NSString *fifoPath = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  if (mkfifo(fifoPath.UTF8String, S_IWUSR | S_IRUSR) != 0) {
    return [[[FBControlCoreError
      describeFormat:@"Failed to create a named pipe for fifo %@ with error '%s'", fifoPath, strerror(errno)]
      inDomain:NSPOSIXErrorDomain]
      failFuture];
  }
  return [FBFuture futureWithResult:fifoPath];
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

- (FBFuture<NSNull *> *)detach
{
  return [FBFuture futureWithResult:NSNull.null];
}

- (NSNull *)contents
{
  return NSNull.null;
}

#pragma mark FBProcessOutput Implementation

- (FBFuture<id<FBProcessFileOutput>> *)providedThroughFile
{
  return [FBFuture futureWithResult:[[FBProcessFileOutput_DirectToFile alloc] initWithFilePath:@"/dev/null"]];
}

- (FBFuture<id<FBDataConsumer>> *)providedThroughConsumer
{
  return [FBFuture futureWithResult:FBNullDataConsumer.new];
}

#pragma mark NSObject

- (NSString *)description
{
  return @"Null Output";
}

@end

@implementation FBProcessOutput_Consumer

#pragma mark Initializers

- (instancetype)initWithConsumer:(id<FBDataConsumer>)consumer logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;
  _logger = logger;

  return self;
}

#pragma mark FBStandardStream

- (FBFuture<NSFileHandle *> *)attachToFileHandle
{
  return [[[self
    attachToPipeOrFileHandle]
    onQueue:self.workQueue map:^(NSPipe *pipe) {
      return pipe.fileHandleForWriting;
    }]
    nameFormat:@"Attach to file handle %@", self.description];
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
    self.reader = [FBFileReader readerWithFileHandle:self.pipe.fileHandleForReading consumer:self.consumer logger:self.logger];
    return [[[self.reader
      startReading]
      mapReplace:self.pipe]
      nameFormat:@"Attach to pipe %@", self.description];
  }];
}

- (FBFuture<NSNull *> *)detach
{
  return [[[[self.reader.finishedReading
    timeout:ProcessDetachDrainTimeout waitingFor:@"Process Reading to Finish"]
    onQueue:self.workQueue chain:^(FBFuture *_) {
      return [self.reader stopReading];
    }]
    onQueue:self.workQueue chain:^(FBFuture *future) {
      NSPipe *pipe = self.pipe;
      [pipe.fileHandleForWriting closeFile];

      self.reader = nil;
      self.pipe = nil;
      return future;
    }]
    nameFormat:@"Detach %@", self.description];
}

- (id<FBDataConsumer>)contents
{
  return self.consumer;
}

#pragma mark FBProcessOutput Implementation

- (FBFuture<id<FBProcessFileOutput>> *)providedThroughFile
{
  return [[[self
    makeFifoOutput]
    onQueue:self.workQueue map:^ id<FBProcessFileOutput> (NSString *fifoPath) {
      return [[FBProcessFileOutput_Consumer alloc] initWithConsumer:self.consumer filePath:fifoPath queue:FBProcessOutput.createWorkQueue];
    }]
    nameFormat:@"Relay %@ to file", self.description];
}

- (FBFuture<id<FBDataConsumer>> *)providedThroughConsumer
{
  return [FBFuture futureWithResult:self.consumer];
}

#pragma mark NSObject

- (NSString *)description
{
  return @"Output to consumer";
}

@end

@implementation FBProcessOutput_Logger

#pragma mark Initializers

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger
{
  id<FBDataConsumer> consumer = [FBLoggingDataConsumer consumerWithLogger:logger];
  self = [super initWithConsumer:consumer logger:logger];
  if (!self) {
    return nil;
  }

  return self;
}

#pragma mark FBStandardStream

- (id<FBControlCoreLogger>)contents
{
  return self.logger;
}

#pragma mark NSObject

- (NSString *)description
{
  return @"Output to logger";
}

@end

@implementation FBProcessOutput_FilePath

#pragma mark Initializers

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
  return [[FBFuture
    onQueue:self.workQueue resolve:^{
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
    }]
    nameFormat:@"Attach to %@", self.description];
}

- (FBFuture<NSFileHandle *> *)attachToPipeOrFileHandle
{
  return [self attachToFileHandle];
}

- (FBFuture<NSNull *> *)detach
{
  return [[FBFuture
    onQueue:self.workQueue resolve:^{
      NSFileHandle *fileHandle = self.fileHandle;
      if (!fileHandle) {
        return [[FBControlCoreError
          describe:@"Cannot Detach Twice"]
          failFuture];
      }
      self.fileHandle = nil;
      [fileHandle closeFile];
      return [FBFuture futureWithResult:NSNull.null];
    }]
    nameFormat:@"Detach from %@", self.description];
}

- (NSString *)contents
{
  return self.filePath;
}

#pragma mark FBProcessOutput Implementation

- (FBFuture<id<FBProcessFileOutput>> *)providedThroughFile
{
  return [FBFuture futureWithResult:[[FBProcessFileOutput_DirectToFile alloc] initWithFilePath:self.filePath]];
}

- (FBFuture<id<FBDataConsumer>> *)providedThroughConsumer
{
  return (FBFuture<id<FBDataConsumer>> *) [FBFileWriter asyncWriterForFilePath:self.filePath];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Output to %@", self.filePath];
}

@end

@implementation FBProcessOutput_Data

#pragma mark Initializers

- (instancetype)initWithMutableData:(NSMutableData *)mutableData
{
  id<FBAccumulatingBuffer> consumer = [FBDataBuffer accumulatingBufferForMutableData:mutableData];
  self = [super initWithConsumer:consumer logger:nil];
  if (!self) {
    return nil;
  }

  _dataConsumer = consumer;

  return self;
}

#pragma mark FBStandardStream

- (NSData *)contents
{
  return self.dataConsumer.data;
}

#pragma mark NSObject

- (NSString *)description
{
  return @"Output to Mutable Data";
}

@end

@implementation FBProcessOutput_String

#pragma mark FBStandardStream

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

#pragma mark NSObject

- (NSString *)description
{
  return @"Output to Mutable String";
}

@end

@interface FBProcessInput ()

@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;
@property (nonatomic, strong, readonly) dispatch_group_t pipeGroup;
@property (nonatomic, strong, nullable, readwrite) NSPipe *pipe;

@end

@interface FBProcessInput_Consumer : FBProcessInput <FBDataConsumer>

@property (nonatomic, strong, nullable, readwrite) id<FBDataConsumer> writer;

@end

@interface FBProcessInput_Data : FBProcessInput_Consumer

- (instancetype)initWithData:(NSData *)data;

@property (nonatomic, strong, readonly) NSData *data;

@end

@interface FBProcessInput_InputStream : FBProcessInput

@property (nonatomic, strong, readonly) NSOutputStream *stream;

@end

@interface NSOutputStream_FBProcessInput : NSOutputStream

@property (nonatomic, weak, readonly) FBProcessInput_InputStream *input;

- (instancetype)initWithInput:(FBProcessInput_InputStream *)input;

@end

@implementation FBProcessInput

#pragma mark Initializers

+ (FBProcessInput<id<FBDataConsumer>> *)inputFromConsumer
{
  return [[FBProcessInput_Consumer alloc] init];
}

+ (FBProcessInput<NSOutputStream *> *)inputFromStream
{
  return [[FBProcessInput_InputStream alloc] init];
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
  _pipeGroup = dispatch_group_create();
  dispatch_group_enter(_pipeGroup);

  return self;
}

#pragma mark FBStandardStream

- (FBFuture<NSFileHandle *> *)attachToFileHandle
{
  return [[[self
    attachToPipeOrFileHandle]
    onQueue:self.workQueue map:^(NSPipe *pipe) {
      return pipe.fileHandleForReading;
    }]
    nameFormat:@"Attach %@ to file handle", self.description];
}

- (FBFuture<NSPipe *> *)attachToPipeOrFileHandle
{
  return [[FBFuture
    onQueue:self.workQueue resolve:^{
      if (self.pipe) {
        return [[FBControlCoreError
          describeFormat:@"Cannot Attach Twice"]
          failFuture];
      }

      NSPipe *pipe = NSPipe.pipe;
      NSError *error = nil;
      id<FBDataConsumer> writer = [FBFileWriter asyncWriterWithFileHandle:pipe.fileHandleForWriting error:&error];
      if (!writer) {
        return [[FBControlCoreError
          describeFormat:@"Failed to create a writer for pipe %@", error]
          failFuture];
      }
      self.pipe = pipe;
      dispatch_group_leave(self.pipeGroup);
      return [FBFuture futureWithResult:pipe];
    }]
    nameFormat:@"Attach %@ to pipe", self.description];
}

- (FBFuture<NSNull *> *)detach
{
  return [[FBFuture
    onQueue:self.workQueue resolve:^{
      NSPipe *pipe = self.pipe;
      if (!pipe) {
        return [[FBControlCoreError
          describeFormat:@"Nothing is attached to %@", self]
          failFuture];
      }

      [pipe.fileHandleForWriting closeFile];
      self.pipe = nil;

      return [FBFuture futureWithResult:NSNull.null];
    }]
    nameFormat:@"Detach %@", self.description];
}

- (id<FBDataConsumer>)contents
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@implementation FBProcessInput_Consumer

#pragma mark FBStandardStream

- (id<FBDataConsumer>)contents
{
  return self;
}

- (FBFuture<NSPipe *> *)attachToPipeOrFileHandle
{
  return [[[super
    attachToPipeOrFileHandle]
    onQueue:self.workQueue fmap:^(NSPipe *pipe) {
      NSError *error = nil;
      id<FBDataConsumer> writer = [FBFileWriter asyncWriterWithFileHandle:pipe.fileHandleForWriting error:&error];
      if (!writer) {
        return [[FBControlCoreError
          describeFormat:@"Failed to create a writer for pipe %@", error]
          failFuture];
      }
      self.writer = writer;
      return [FBFuture futureWithResult:pipe];
    }]
    nameFormat:@"Attach %@ to pipe", self.description];
}

- (FBFuture<NSNull *> *)detach
{
  return [[[super
    detach]
    onQueue:self.workQueue notifyOfCompletion:^(id _) {
      self.writer = nil;
    }]
    nameFormat:@"Detach %@", self.description];
}

#pragma mark FBDataConsumer

- (void)consumeData:(NSData *)data
{
  [self.writer consumeData:data];
}

- (void)consumeEndOfFile
{
  [self.writer consumeEndOfFile];
}

#pragma mark NSObject

- (NSString *)description
{
  return @"Input to consumer";
}

@end

@implementation FBProcessInput_Data

#pragma mark Initializers

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
  return [[[super
    attachToPipeOrFileHandle]
    onQueue:self.workQueue map:^(NSPipe *pipe) {
      [self.writer consumeData:self.data];
      [self.writer consumeEndOfFile];
      return pipe;
    }]
    nameFormat:@"Attach %@ to pipe", self.description];
}

- (NSData *)contents
{
  return self.data;
}

#pragma mark NSObject

- (NSString *)description
{
  return @"Input to Data";
}

@end

@implementation FBProcessInput_InputStream

#pragma mark Initializers

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _stream = [[NSOutputStream_FBProcessInput alloc] initWithInput:self];

  return self;
}

#pragma mark FBStandardStream

- (NSOutputStream *)contents
{
  return self.stream;
}

- (NSString *)description
{
  return @"Input to NSOutputStream";
}

@end

@implementation NSOutputStream_FBProcessInput

#pragma mark Initializers

- (instancetype)initWithInput:(FBProcessInput_InputStream *)input
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _input = input;

  return self;
}

#pragma mark NSOutputStream

static NSTimeInterval const StreamOpenTimeout = 5.0;

- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len
{
  int fileDescriptor = self.input.pipe.fileHandleForWriting.fileDescriptor;
  if (fileDescriptor == 0) {
    return -1;
  }
  return write(fileDescriptor, buffer, len);
}

- (void)open
{
  long success = dispatch_group_wait(self.input.pipeGroup, FBCreateDispatchTimeFromDuration(StreamOpenTimeout));
  NSAssert(success == 0, @"Pipe for NSOutputStream did not open in %f seconds", StreamOpenTimeout);
}

- (void)close
{
  [self.input.pipe.fileHandleForWriting closeFile];
}

- (BOOL)hasSpaceAvailable
{
  return YES;
}

@end
