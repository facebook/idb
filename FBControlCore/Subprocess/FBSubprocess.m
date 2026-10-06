/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSubprocess.h"

#include <spawn.h>

#import "ControlCoreLogger.h"
#import "DataConsumer.h"
#import "FBControlCore-Swift.h"
#import "FBControlCore-SwiftImport.h"
#import "FBDataBuffer.h"
#import "FBProcessIO.h"
#import "FBProcessStream.h"

static BOOL AddOutputFileActions(posix_spawn_file_actions_t *fileActions, FBProcessStreamAttachment *attachment, int targetFileDescriptor, NSError **error)
{
  if (!attachment) {
    return YES;
  }
  NSCParameterAssert(attachment.mode == FBProcessStreamAttachmentModeOutput);
  // Files do not need to be closed in the launched process as POSIX_SPAWN_CLOEXEC_DEFAULT does this for us.
  int sourceFileDescriptor = attachment.fileDescriptor;
  int status = posix_spawn_file_actions_adddup2(fileActions, sourceFileDescriptor, targetFileDescriptor);
  if (status != 0) {
    return [[ControlCoreError
             describe:[NSString stringWithFormat:@"Failed to dup input %d, to %d: %s", sourceFileDescriptor, targetFileDescriptor, strerror(status)]]
            failBool:error];
  }
  return YES;
}

static BOOL AddInputFileActions(posix_spawn_file_actions_t *fileActions, FBProcessStreamAttachment *attachment, int targetFileDescriptor, NSError **error)
{
  if (!attachment) {
    return YES;
  }
  NSCParameterAssert(attachment.mode == FBProcessStreamAttachmentModeInput);
  // Files do not need to be closed in the launched process as POSIX_SPAWN_CLOEXEC_DEFAULT does this for us.
  int sourceFileDescriptor = attachment.fileDescriptor;
  int status = posix_spawn_file_actions_adddup2(fileActions, sourceFileDescriptor, targetFileDescriptor);
  if (status != 0) {
    return [[ControlCoreError
             describe:[NSString stringWithFormat:@"Failed to dup input %d, to %d: %s", sourceFileDescriptor, targetFileDescriptor, strerror(status)]]
            failBool:error];
  }
  return YES;
}

@interface FBSubprocess ()

@property (nonatomic, readonly, copy) NSString *launchPath;
@property (nonatomic, readonly, copy) NSArray<NSString *> *arguments;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, readonly, strong) FBProcessIO *io;
@property (nonatomic, readonly, strong) dispatch_queue_t queue;

@end

@implementation FBSubprocess

@synthesize exitCode = _exitCode;
@synthesize processIdentifier = _processIdentifier;
@synthesize signal = _signal;
@synthesize statLoc = _statLoc;

#pragma mark Initializers

- (instancetype)initWithProcessIdentifier:(pid_t)processIdentifier statLoc:(FBFuture<NSNumber *> *)statLoc exitCode:(FBFuture<NSNumber *> *)exitCode signal:(FBFuture<NSNumber *> *)signal launchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment io:(FBProcessIO *)io queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _launchPath = [launchPath copy];
  _arguments = [arguments copy];
  _environment = [environment copy];
  _io = io;
  _processIdentifier = processIdentifier;
  _exitCode = exitCode;
  _signal = signal;
  _statLoc = statLoc;
  _queue = queue;

  return self;
}

+ (FBFuture<FBSubprocess *> *)launchProcessWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment io:(FBProcessIO *)io logger:(id<ControlCoreLogger>)logger
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.task", DISPATCH_QUEUE_SERIAL);
  return [[io
           attach]
          onQueue:queue
          fmap:^(FBProcessIOAttachment *attachment) {
            NSError *error = nil;
            FBSubprocess *process = [FBSubprocess processWithLaunchPath:launchPath arguments:arguments environment:environment io:io attachment:attachment queue:queue logger:logger error:&error];
            if (!process) {
              return [FBFuture futureWithError:error];
            }
            return [FBFuture futureWithResult:process];
          }];
}

#pragma mark Public Methods

- (FBFuture<NSNumber *> *)exitedWithCodes:(NSSet<NSNumber *> *)acceptableExitCodes
{
  return [[FBMutableFuture.future
           resolveFromFuture:self.exitCode]
          onQueue:self.queue
          fmap:^(NSNumber *exitCode) {
            return [[FBSubprocess confirmExitCode:exitCode.intValue isAcceptable:acceptableExitCodes stdErr:self.stdErr] mapReplace:exitCode];
          }];
}

- (FBFuture<NSNumber *> *)sendSignal:(int)signo
{
  return [[FBFuture
           onQueue:self.queue
           resolve:^{
             if (self.statLoc.hasCompleted) {
               return self.statLoc;
             }
             kill(self.processIdentifier, signo);
             return self.statLoc;
           }]
          mapReplace:@(signo)];
}

- (FBFuture<NSNumber *> *)sendSignal:(int)signo backingOffToKillWithTimeout:(NSTimeInterval)timeout logger:(id<ControlCoreLogger>)logger
{
  return [[[self
            sendSignal:signo]
           onQueue:self.queue
           timeout:timeout
           handler:^{
             [logger log:[NSString stringWithFormat:@"Process %d didn't exit after wait for %f seconds for sending signal %d, sending SIGKILL now.", self.processIdentifier, timeout, signo]];
             return [self sendSignal:SIGKILL];
           }]
          mapReplace:@(signo)];
}

#pragma mark Properties

- (nullable id)stdIn
{
  return [self.io.stdIn contents];
}

- (nullable id)stdOut
{
  return [self.io.stdOut contents];
}

- (nullable id)stdErr
{
  return [self.io.stdErr contents];
}

#pragma mark Private

+ (FBFuture<NSNull *> *)confirmExitCode:(int)exitCode isAcceptable:(NSSet<NSNumber *> *)acceptableExitCodes stdErr:(nullable id)stdErr
{
  if (acceptableExitCodes == nil) {
    return FBFuture.empty;
  }
  if ([acceptableExitCodes containsObject:@(exitCode)]) {
    return FBFuture.empty;
  }
  NSString *description = [NSString stringWithFormat:@"Exit Code %d is not acceptable %@", exitCode, [CollectionInformation oneLineDescriptionFromArray:acceptableExitCodes.allObjects]];
  NSString *capturedStdErr = [self capturedErrorMessage:stdErr];
  if (capturedStdErr.length > 0) {
    description = [NSString stringWithFormat:@"%@: %@", description, capturedStdErr];
  }
  return (FBFuture *)[[ControlCoreError
                       describe:description]
                      failFuture];
}

// Only output captured by the `...ToLoggerAndErrorMessage:` builder options is appended; it is bounded to `FBProcessOutputErrorMessageLength`, whereas other in-memory output is the caller's to read and may be arbitrarily large.
+ (nullable NSString *)capturedErrorMessage:(nullable id)output
{
  if (![output conformsToProtocol:@protocol(AccumulatingBuffer)]) {
    return nil;
  }
  NSData *data = [(id<AccumulatingBuffer>)output data];
  // Lossy, because a strict decode returns nil for any byte that is not UTF-8, dropping the whole message.
  NSString *string = nil;
  [NSString stringEncodingForData:data
                  encodingOptions:@{
     NSStringEncodingDetectionSuggestedEncodingsKey : @[@(NSUTF8StringEncoding)],
     NSStringEncodingDetectionUseOnlySuggestedEncodingsKey : @YES,
     NSStringEncodingDetectionAllowLossyKey : @YES,
   }
                  convertedString:&string
              usedLossyConversion:NULL];
  return [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

+ (FBSubprocess *)processWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment io:(FBProcessIO *)io attachment:(FBProcessIOAttachment *)attachment queue:(dispatch_queue_t)queue logger:(id<ControlCoreLogger>)logger error:(NSError **)error
{
  char *argv[arguments.count + 2]; // 0th arg is launch path, last arg is NULL
  argv[0] = (char *) launchPath.UTF8String;
  argv[arguments.count + 1] = NULL;
  for (NSUInteger index = 0; index < arguments.count; index++) {
    argv[index + 1] = (char *) arguments[index].UTF8String;
  }

  NSArray<NSString *> *environmentNames = environment.allKeys;
  char *envp[environment.count + 1];
  envp[environment.count] = NULL;
  for (NSUInteger index = 0; index < environmentNames.count; index++) {
    NSString *name = environmentNames[index];
    NSString *value = [NSString stringWithFormat:@"%@=%@", name, environment[name]];
    envp[index] = (char *) value.UTF8String;
  }

  posix_spawn_file_actions_t fileActions;
  posix_spawn_file_actions_init(&fileActions);

  if (!AddInputFileActions(&fileActions, attachment.stdIn, STDIN_FILENO, error)) {
    return nil;
  }
  if (!AddOutputFileActions(&fileActions, attachment.stdOut, STDOUT_FILENO, error)) {
    return nil;
  }
  if (!AddOutputFileActions(&fileActions, attachment.stdErr, STDERR_FILENO, error)) {
    return nil;
  }

  posix_spawnattr_t spawnAttributes;
  posix_spawnattr_init(&spawnAttributes);

  // No signals in the child process will be masked from whatever is set in the current process.
  sigset_t mask;
  sigemptyset(&mask);
  posix_spawnattr_setsigmask(&spawnAttributes, &mask);

  // All signals in the new process should have the default disposition.
  sigfillset(&mask);
  posix_spawnattr_setsigdefault(&spawnAttributes, &mask);

  // Closes all file descriptors in the child that aren't duped. This prevents any file descriptors other than the ones we define being inherited by children.
  posix_spawnattr_setflags(&spawnAttributes, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK);

  pid_t processIdentifier;
  int status = posix_spawn(&processIdentifier, argv[0], &fileActions, &spawnAttributes, argv, envp);
  posix_spawn_file_actions_destroy(&fileActions);
  posix_spawnattr_destroy(&spawnAttributes);
  if (status != 0) {
    return [[ControlCoreError
             describe:[NSString stringWithFormat:@"Failed to launch %@ with error %s", [self launchDescriptionWithLaunchPath:launchPath arguments:arguments environment:environment io:io], strerror(status)]]
            fail:error];
  }
  NSString *processName = launchPath.lastPathComponent;
  [logger log:[NSString stringWithFormat:@"%@ Launched with pid %d", processName, processIdentifier]];

  FBMutableFuture<NSNumber *> *statLoc = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *exitCode = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *signal = FBMutableFuture.future;
  [self resolveProcessCompletion:processIdentifier attachment:attachment statLoc:statLoc exitCode:exitCode signal:signal processName:processName logger:logger];
  return [[self alloc] initWithProcessIdentifier:processIdentifier statLoc:statLoc exitCode:exitCode signal:signal launchPath:launchPath arguments:arguments environment:environment io:io queue:queue];
}

+ (NSString *)launchDescriptionWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment io:(FBProcessIO *)io
{
  return [NSString stringWithFormat:@"Process Launch %@ | Arguments %@ | Environment %@ | Output %@", launchPath, [CollectionInformation oneLineDescriptionFromArray:arguments], [CollectionInformation oneLineDescriptionFromDictionary:environment], io];
}

+ (void)resolveProcessCompletion:(pid_t)processIdentifier attachment:(FBProcessIOAttachment *)attachment statLoc:(FBMutableFuture<NSNumber *> *)statLoc exitCode:(FBMutableFuture<NSNumber *> *)exitCode signal:(FBMutableFuture<NSNumber *> *)signal processName:(NSString *)processName logger:(id<ControlCoreLogger>)logger
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.task.posix_spawn.wait", DISPATCH_QUEUE_SERIAL);
  dispatch_source_t source = dispatch_source_create(
    DISPATCH_SOURCE_TYPE_PROC,
    (uintptr_t) processIdentifier,
    DISPATCH_PROC_EXIT,
    queue
  );
  dispatch_source_set_event_handler(source, ^{
    int status = 0;
    // The exit event can arrive before the child is reapable, and a WNOHANG reap that returns 0 leaves the status at zero, which decodes as a clean exit.
    pid_t reaped = waitpid(processIdentifier, &status, WNOHANG);
    if (reaped == 0) {
      reaped = waitpid(processIdentifier, &status, 0);
    }
    if (reaped != processIdentifier) {
      [logger log:[NSString stringWithFormat:@"Failed to get the exit status with waitpid: %s", strerror(errno)]];
    }

    // Resolve all of the related process finshed futures now, so that they do not need asynchronous resolution.
    [ProcessSpawnCommandHelpers
     resolveProcessFinishedWithStatLoc:status
     inTeardownOfIOAttachment:attachment
     statLocFuture:statLoc
     exitCodeFuture:exitCode
     signalFuture:signal
     processIdentifier:processIdentifier
     processName:processName
     queue:queue
     logger:logger];

    // We only need a single notification and the dispatch_source must be retained until we resolve the future.
    // Cancelling the source at the end will release the source as the event handler will no longer be referenced.
    dispatch_cancel(source);
  });
  dispatch_resume(source);
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Process %@ | pid %d | State %@", [FBSubprocess launchDescriptionWithLaunchPath:self.launchPath arguments:self.arguments environment:self.environment io:self.io], self.processIdentifier, self.statLoc];
}

@end
