/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTask.h"

#import "FBRunLoopSpinner.h"
#import "FBTaskConfiguration.h"
#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBFileConsumer.h"
#import "FBPipeReader.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

NSString *const FBTaskErrorDomain = @"com.facebook.FBControlCore.task";
FBTerminationHandleType const FBTerminationHandleTypeTask = @"Task";

@interface FBTaskOutput : NSObject

- (NSString *)contents;
- (id)attachWithError:(NSError **)error;
- (void)teardownResources;

@end

@interface FBTaskOutput_File : FBTaskOutput

@property (nonatomic, copy, nullable, readonly) NSString *filePath;
@property (nonatomic, strong, nullable, readwrite) NSFileHandle *fileHandle;

@end

@interface FBTaskOutput_Consumer : FBTaskOutput

@property (nonatomic, strong, nullable, readwrite) FBPipeReader *reader;
@property (nonatomic, strong, nullable, readwrite) FBAccumilatingFileConsumer *dataConsumer;
@property (nonatomic, strong, nullable, readwrite) id<FBFileConsumer> consumer;

@end

@interface FBTaskConfiguration (FBTaskOutput)

- (FBTaskOutput *)createTaskOutput;

@end

@implementation FBTaskOutput

- (NSString *)contents
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (id)attachWithError:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (void)teardownResources
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

@end

@implementation FBTaskOutput_Consumer

- (instancetype)initWithConsumer:(id<FBFileConsumer>)consumer dataConsumer:(FBAccumilatingFileConsumer *)dataConsumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;
  _dataConsumer = dataConsumer;

  return self;
}

- (NSString *)contents
{
  return [[[NSString alloc]
    initWithData:self.dataConsumer.data encoding:NSUTF8StringEncoding]
    stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (id)attachWithError:(NSError **)error
{
  NSAssert(self.reader == nil, @"Cannot attach when already attached to a reader");
  self.reader = [FBPipeReader pipeReaderWithConsumer:self.consumer];
  if (![self.reader startReadingWithError:error]) {
    self.reader = nil;
    return nil;
  }
  return self.reader.pipe;
}

- (void)teardownResources
{
  [self.reader stopReadingWithError:nil];
  self.reader = nil;
}

@end

@implementation FBTaskOutput_File

- (instancetype)initWithPath:(NSString *)filePath
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _filePath = filePath;
  return self;
}

- (NSString *)contents
{
  @synchronized(self) {
    return [NSString stringWithContentsOfFile:self.filePath usedEncoding:nil error:nil];
  }
}

- (id)attachWithError:(NSError **)error
{
  NSAssert(self.fileHandle == nil, @"Cannot attach when already attached to file %@", self.fileHandle);
  if (!self.filePath) {
    self.fileHandle = NSFileHandle.fileHandleWithNullDevice;
    return self.fileHandle;
  }

  if (![NSFileManager.defaultManager createFileAtPath:self.filePath contents:nil attributes:nil]) {
    return [[FBControlCoreError
      describeFormat:@"Could not create file for writing at %@", self.filePath]
      fail:error];
  }
  self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.filePath];
  return self.fileHandle;
}

- (void)teardownResources
{
  [self.fileHandle closeFile];
  self.fileHandle = nil;
}

@end

@interface FBTaskProcess : NSObject

@property (nonatomic, assign, readonly) int terminationStatus;
@property (nonatomic, assign, readonly) BOOL isRunning;

- (pid_t)launchWithError:(NSError **)error terminationHandler:(void(^)(FBTaskProcess *))terminationHandler;
- (void)mountStandardOut:(id)stdOut;
- (void)mountStandardErr:(id)stdOut;
- (void)terminate;

@end

@interface FBTaskProcess_NSTask : FBTaskProcess

@property (nonatomic, strong, readwrite) NSTask *task;

- (instancetype)initWithTask:(NSTask *)task;

@end

@implementation FBTaskProcess

+ (instancetype)fromConfiguration:(FBTaskConfiguration *)configuration
{
  NSTask *task = [[NSTask alloc] init];
  task.environment = configuration.environment;
  task.launchPath = configuration.launchPath;
  task.arguments = configuration.arguments;
  return [[FBTaskProcess_NSTask alloc] initWithTask:task];
}

- (BOOL)isRunning
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
}

- (int)terminationStatus
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return 0;
}

- (void)mountStandardOut:(id)stdOut
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (void)mountStandardErr:(id)stdOut
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (void)terminate
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (pid_t)launchWithError:(NSError **)error terminationHandler:(void(^)(FBTaskProcess *))terminationHandler
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return 0;
}

@end

@implementation FBTaskProcess_NSTask

- (instancetype)initWithTask:(NSTask *)task
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _task = task;
  return self;
}

- (pid_t)processIdentifier
{
  return self.task.processIdentifier;
}

- (int)terminationStatus
{
  return self.task.terminationStatus;
}

- (BOOL)isRunning
{
  return self.task.isRunning;
}

- (void)mountStandardOut:(id)stdOut
{
  self.task.standardOutput = stdOut;
}

- (void)mountStandardErr:(id)stdErr
{
  self.task.standardError = stdErr;
}

- (pid_t)launchWithError:(NSError **)error terminationHandler:(void(^)(FBTaskProcess *))terminationHandler
{
  self.task.terminationHandler = ^(NSTask *_) {
    [self terminate];
    terminationHandler(self);
  };
  [self.task launch];
  return self.task.processIdentifier;
}

- (void)terminate
{
  [self.task terminate];
  [self.task waitUntilExit];
  self.task.terminationHandler = nil;
}

@end

@interface FBTask ()

@property (nonatomic, copy, readonly) NSSet<NSNumber *> *acceptableStatusCodes;

@property (nonatomic, strong, nullable, readwrite) FBTaskProcess *process;
@property (nonatomic, strong, nullable, readwrite) FBTaskOutput *stdOutSlot;
@property (nonatomic, strong, nullable, readwrite) FBTaskOutput *stdErrSlot;
@property (nonatomic, copy, nullable, readwrite) NSString *configurationDescription;

@property (atomic, assign, readwrite) pid_t processIdentifier;
@property (atomic, assign, readwrite) BOOL completedTeardown;
@property (atomic, copy, nullable, readwrite) NSString *emittedError;
@property (atomic, copy, nullable, readwrite) void (^terminationHandler)(FBTask *);

@end

@implementation FBTask

#pragma mark Initializers

+ (FBTaskOutput *)createTaskOutput:(id)output
{
  if ([output isKindOfClass:NSString.class]) {
     return [[FBTaskOutput_File alloc] initWithPath:output];
  }
  id<FBFileConsumer> consumer = nil;
  NSMutableData *data = [NSMutableData data];
  if ([output conformsToProtocol:@protocol(FBFileConsumer)]) {
    consumer = output;
  }
  else if ([output conformsToProtocol:@protocol(FBControlCoreLogger)]) {
    id<FBControlCoreLogger> logger = output;
    consumer = [FBLineFileConsumer asynchronousReaderWithConsumer:^(NSString *line) {
      [logger log:line];
    }];
  }
  else {
    NSAssert([output isKindOfClass:NSMutableData.class], @"Unexpected output type %@", output);
    data = output;
  }
  FBAccumilatingFileConsumer *dataConsumer = [[FBAccumilatingFileConsumer alloc] initWithMutableData:data];
  consumer = consumer ? [FBCompositeFileConsumer consumerWithConsumers:@[consumer, dataConsumer]] : dataConsumer;
  return [[FBTaskOutput_Consumer alloc] initWithConsumer:consumer dataConsumer:dataConsumer];
}

+ (instancetype)taskWithConfiguration:(FBTaskConfiguration *)configuration
{
  FBTaskProcess *task = [FBTaskProcess fromConfiguration:configuration];
  FBTaskOutput *stdOut = [self createTaskOutput:configuration.stdOut];
  FBTaskOutput *stdErr = [self createTaskOutput:configuration.stdErr];
  return [[self alloc] initWithProcess:task stdOut:stdOut stdErr:stdErr acceptableStatusCodes:configuration.acceptableStatusCodes configurationDescription:configuration.description];
}

- (instancetype)initWithProcess:(FBTaskProcess *)process stdOut:(FBTaskOutput *)stdOut stdErr:(FBTaskOutput *)stdErr acceptableStatusCodes:(NSSet<NSNumber *> *)acceptableStatusCodes configurationDescription:(NSString *)configurationDescription
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _process = process;
  _acceptableStatusCodes = acceptableStatusCodes;
  _stdOutSlot = stdOut;
  _stdErrSlot = stdErr;
  _configurationDescription = configurationDescription;

  return self;
}

#pragma mark - FBTerminationHandle Protocol

- (void)terminate
{
  [self terminateWithErrorMessage:nil];
}

- (FBTerminationHandleType)type
{
  return FBTerminationHandleTypeTask;
}

#pragma mark - FBTask Protocl

#pragma mark Starting

- (instancetype)startAsynchronously
{
  return [self launchWithTerminationHandler:nil];
}

- (instancetype)startAsynchronouslyWithTerminationHandler:(void (^)(FBTask *task))handler
{
  return [self launchWithTerminationHandler:handler];
}

- (instancetype)startSynchronouslyWithTimeout:(NSTimeInterval)timeout
{
  [self launchWithTerminationHandler:nil];

  NSError *error = nil;
  if (![self waitForCompletionWithTimeout:timeout error:&error]) {
    return [self terminateWithErrorMessage:error.description];
  }
  return [self terminateWithErrorMessage:nil];
}

#pragma mark Awaiting Completion

- (BOOL)waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;
{
  BOOL completed = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^ BOOL {
    return !self.process.isRunning;
  }];

  if (!completed) {
    return [[FBControlCoreError
      describeFormat:@"Launched process '%@' took longer than %f seconds to terminate", self, timeout]
      failBool:error];
  }
  [self terminateWithErrorMessage:nil];
  return YES;
}

#pragma mark Accessors

- (NSString *)stdOut
{
  return [self.stdOutSlot contents];
}

- (NSString *)stdErr
{
  return [self.stdErrSlot contents];
}

- (nullable NSError *)error
{
  if (!self.emittedError) {
    return nil;
  }

  FBControlCoreError *error = [[[[FBControlCoreError
    describe:self.emittedError]
    inDomain:FBTaskErrorDomain]
    extraInfo:@"stdout" value:self.stdOut]
    extraInfo:@"stderr" value:self.stdErr];

  if (!self.process.isRunning) {
    [error extraInfo:@"exitcode" value:@(self.process.terminationStatus)];
  }
  return [error build];
}

- (BOOL)hasTerminated
{
  return self.completedTeardown;
}

- (BOOL)wasSuccessful
{
  @synchronized(self)
  {
    return self.hasTerminated && self.emittedError == nil;
  }
}

#pragma mark Private

- (instancetype)launchWithTerminationHandler:(void (^)(FBTask *task))handler
{
  // Since the FBTask may not be returned by anyone and is asynchronous, it needs to be retained.
  // This Retain is matched by a release in -[FBTask completeTermination].
  CFRetain((__bridge CFTypeRef)(self));

  self.terminationHandler = handler;

  NSError *error = nil;
  id stdOut = [self.stdOutSlot attachWithError:&error];
  if (!stdOut) {
    return [self terminateWithErrorMessage:error.description];
  }
  [self.process mountStandardOut:stdOut];

  id stdErr = [self.stdErrSlot attachWithError:&error];
  if (!stdErr) {
    return [self terminateWithErrorMessage:error.description];
  }
  [self.process mountStandardErr:stdErr];

  pid_t pid = [self.process launchWithError:&error terminationHandler:^(FBTaskProcess *_) {
    [self terminateWithErrorMessage:nil];
  }];
  if (pid < 1) {
    return [self terminateWithErrorMessage:error.description];
  }
  self.processIdentifier = pid;

  return self;
}

- (instancetype)terminateWithErrorMessage:(nullable NSString *)errorMessage
{
  @synchronized(self) {
    if (!self.emittedError) {
      self.emittedError = errorMessage;
    }
    if (self.completedTeardown) {
      return self;
    }

    [self teardownProcess];
    [self teardownResources];
    [self completeTermination];
    self.completedTeardown = YES;
    return self;
  }
}

- (void)teardownProcess
{
  if (self.process.isRunning) {
    [self.process terminate];
  }
}

- (void)teardownResources
{
  [self.stdOutSlot teardownResources];
  [self.stdErrSlot teardownResources];
}

- (void)completeTermination
{
  NSAssert(self.process.isRunning == NO, @"Process should be terminated before calling completeTermination");
  if (self.emittedError == nil && [self.acceptableStatusCodes containsObject:@(self.process.terminationStatus)] == NO) {
    self.emittedError = [NSString stringWithFormat:@"Returned non-zero status code %d", self.process.terminationStatus];
  }

  // Matches the release in -[FBTask launchWithTerminationHandler:].
  CFRelease((__bridge CFTypeRef)(self));

  void (^terminationHandler)(FBTask *) = self.terminationHandler;
  if (!terminationHandler) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    terminationHandler(self);
  });
  self.terminationHandler = nil;
}

- (NSString *)description
{
  return [NSString
    stringWithFormat:@"%@ | Has Terminated %d",
    self.configurationDescription,
    self.hasTerminated
  ];
}

@end

#pragma clang diagnostic pop
