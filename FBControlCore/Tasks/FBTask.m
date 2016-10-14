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
#import "FBLineReader.h"
#import "FBControlCoreLogger.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

NSString *const FBTaskErrorDomain = @"com.facebook.FBControlCore.task";

@interface FBTaskOutput : NSObject

- (NSString *)contents;
- (id)attachWithError:(NSError **)error;
- (void)teardownResources;

@end

@interface FBTaskOutput_Memory : FBTaskOutput

@property (nonatomic, strong, readonly) NSMutableData *data;
@property (nonatomic, strong, nullable, readwrite) NSPipe *pipe;

@end

@interface FBTaskOutput_File : FBTaskOutput

@property (nonatomic, copy, nullable, readonly) NSString *filePath;
@property (nonatomic, strong, nullable, readwrite) NSFileHandle *fileHandle;

@end

@interface FBTaskOutput_LineReader : FBTaskOutput_Memory

@property (nonatomic, strong, nullable, readwrite) FBLineReader *reader;

@end

@interface FBTaskOutput_Logger : FBTaskOutput_LineReader

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

@implementation FBTaskOutput_Memory

- (instancetype)initWithData:(NSMutableData *)data
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _data = data;
  return self;
}

- (NSString *)contents
{
  @synchronized(self) {
    return [[[NSString alloc]
      initWithData:self.data encoding:NSUTF8StringEncoding]
      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  }
}

- (id)attachWithError:(NSError **)error
{
  NSAssert(self.pipe == nil, @"Cannot attach when already attached to pipe %@", self.pipe);
  self.pipe = [NSPipe pipe];
  self.pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
    [self dataAvailable:handle.availableData];
  };
  return self.pipe;
}

- (void)teardownResources
{
  self.pipe.fileHandleForReading.readabilityHandler = nil;
  self.pipe = nil;
}

- (void)dataAvailable:(NSData *)data
{
  @synchronized(self) {
    [self.data appendData:data];
  }
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

@implementation FBTaskOutput_LineReader

- (instancetype)initWithReader:(FBLineReader *)reader
{
  self = [super initWithData:NSMutableData.data];
  if (!self) {
    return nil;
  }

  _reader = reader;
  return self;
}

- (void)dataAvailable:(NSData *)data
{
  [super dataAvailable:data];
  [self.reader consumeData:data];
}

@end

@implementation FBTaskOutput_Logger

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger
{
  FBLineReader *reader = [FBLineReader lineReaderWithConsumer:^(NSString *line) {
    [logger log:line];
  }];

  return [super initWithReader:reader];
}

@end

@interface FBTask ()

@property (nonatomic, copy, readonly) NSSet<NSNumber *> *acceptableStatusCodes;

@property (nonatomic, strong, readwrite) NSTask *task;
@property (nonatomic, strong, nullable, readwrite) FBTaskOutput *stdOutSlot;
@property (nonatomic, strong, nullable, readwrite) FBTaskOutput *stdErrSlot;

@property (nonatomic, copy, nullable, readwrite) void (^terminationHandler)(FBTask *);
@property (atomic, assign, readwrite) BOOL hasTerminated;
@property (atomic, strong, readwrite) NSError *runningError;

@end

@implementation FBTask

#pragma mark Initializers

+ (FBTaskOutput *)createTaskOutput:(id)output
{
  if ([output isKindOfClass:NSMutableData.class]) {
    return [[FBTaskOutput_Memory alloc] initWithData:output];
  }
  if ([output isKindOfClass:FBLineReader.class]) {
    return [[FBTaskOutput_LineReader alloc] initWithReader:output];
  }
  if ([output conformsToProtocol:@protocol(FBControlCoreLogger)]) {
    return [[FBTaskOutput_Logger alloc] initWithLogger:output];
  }
  return [[FBTaskOutput_File alloc] initWithPath:output];
}

+ (instancetype)taskWithConfiguration:(FBTaskConfiguration *)configuration
{
  NSTask *task = [configuration createNSTask];
  FBTaskOutput *stdOut = [self createTaskOutput:configuration.stdOut];
  FBTaskOutput *stdErr = [self createTaskOutput:configuration.stdErr];
  return [[self alloc] initWithTask:task acceptableStatusCodes:configuration.acceptableStatusCodes stdOut:stdOut stdErr:stdErr];
}

- (instancetype)initWithTask:(NSTask *)task acceptableStatusCodes:(NSSet<NSNumber *> *)acceptableStatusCodes stdOut:(FBTaskOutput *)stdOut stdErr:(FBTaskOutput *)stdErr
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _task = task;
  _acceptableStatusCodes = acceptableStatusCodes;
  _stdOutSlot = stdOut;
  _stdErrSlot = stdErr;

  return self;
}

#pragma mark - FBTerminationHandle Protocol

- (void)terminate
{
  @synchronized(self) {
    if (self.hasTerminated) {
      return;
    }

    [self teardownTask];
    [self teardownResources];
    [self completeTermination];
  }
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
  BOOL completed = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^BOOL{
    return !self.task.isRunning;
  }];

  if (!completed) {
    NSString *message = [NSString stringWithFormat:
      @"Shell command '%@' took longer than %f seconds to execute",
      self.task,
      timeout
    ];
    self.runningError = [self errorForDescription:message];
  }

  [self terminate];
  return self;
}

- (instancetype)launchWithTerminationHandler:(void (^)(FBTask *task))handler
{
  // Since the FBTask may not be returned by anyone and is asynchronous, it needs to be retained.
  // This Retain is matched by a release in -[FBTask completeTermination].
  CFRetain((__bridge CFTypeRef)(self));

  self.terminationHandler = handler;
  self.task.terminationHandler = ^(NSTask *_) {
    [self terminate];
  };

  NSError *error = nil;
  id stdOut = [self.stdOutSlot attachWithError:&error];
  if (!stdOut) {
    [self terminate];
    return self;
  }
  self.task.standardOutput = stdOut;

  id stdErr = [self.stdErrSlot attachWithError:&error];
  if (!stdErr) {
    [self terminate];
    return self;
  }
  self.task.standardError = stdErr;

  [self.task launch];
  return self;
}

#pragma mark Accessors

- (pid_t)processIdentifier
{
  return self.task.processIdentifier;
}

- (NSString *)stdOut
{
  return [self.stdOutSlot contents];
}

- (NSString *)stdErr
{
  return [self.stdErrSlot contents];
}

- (NSError *)error
{
  return self.runningError;
}

- (BOOL)wasSuccessful
{
  @synchronized(self)
  {
    return self.hasTerminated && self.runningError == nil;
  }
}

#pragma mark Private

- (void)teardownTask
{
  if (self.task.isRunning) {
    [self.task terminate];
    [self.task waitUntilExit];
  }
  self.task.terminationHandler = nil;
}

- (void)teardownResources
{
  [self.stdOutSlot teardownResources];
  [self.stdErrSlot teardownResources];
}

- (void)completeTermination
{
  if (self.runningError == nil && [self.acceptableStatusCodes containsObject:@(self.task.terminationStatus)] == NO) {
    NSString *description = [NSString stringWithFormat:@"Returned non-zero status code %d", self.task.terminationStatus];
    self.runningError = [self errorForDescription:description];
  }

  // Matches the release in -[FBTask launchWithTerminationHandler:].
  CFRelease((__bridge CFTypeRef)(self));
  self.hasTerminated = YES;

  void (^terminationHandler)(FBTask *) = self.terminationHandler;
  if (!terminationHandler) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    terminationHandler(self);
  });
  self.terminationHandler = nil;
}

- (NSError *)errorForDescription:(NSString *)description
{
  NSParameterAssert(description);
  NSMutableDictionary *userInfo = [@{
    NSLocalizedDescriptionKey : description,
  } mutableCopy];
  if (self.stdOut) {
    userInfo[@"stdout"] = self.stdOut;
  }
  if (self.stdErr) {
    userInfo[@"stderr"] = self.stdErr;
  }

  if (!self.task.isRunning) {
    userInfo[@"exitcode"] = @(self.task.terminationStatus);
  }

  return [NSError errorWithDomain:FBTaskErrorDomain code:0 userInfo:userInfo];
}

- (NSString *)description
{
  @synchronized(self) {
    return self.task.description;
  }
}

@end

#pragma clang diagnostic pop
