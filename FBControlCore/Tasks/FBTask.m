/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTask.h"

#include <spawn.h>

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBDataBuffer.h"
#import "FBDataConsumer.h"
#import "FBFileWriter.h"
#import "FBLaunchedProcess.h"
#import "FBProcessIO.h"
#import "FBProcessStream.h"
#import "FBProcessSpawnConfiguration.h"

NSString *const FBTaskErrorDomain = @"com.facebook.FBControlCore.task";

static BOOL AddOutputFileActions(posix_spawn_file_actions_t *fileActions, FBProcessStreamAttachment *attachment, int targetFileDescriptor, NSError **error)
{
  if (!attachment) {
    return YES;
  }
  NSCParameterAssert(attachment.mode == FBProcessStreamAttachmentModeOutput);
  // dup the write end of the pipe to the target file descriptor i.e. stdout
  // Files do not need to be closed in the launched process as POSIX_SPAWN_CLOEXEC_DEFAULT does this for us.
  int sourceFileDescriptor = attachment.fileDescriptor;
  int status = posix_spawn_file_actions_adddup2(fileActions, sourceFileDescriptor, targetFileDescriptor);
  if (status != 0) {
    return [[FBControlCoreError
      describeFormat:@"Failed to dup input %d, to %d: %s", sourceFileDescriptor, targetFileDescriptor, strerror(status)]
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
  // dup the read end of the pipe to the target file descriptor i.e. stdin
  // Files do not need to be closed in the launched process as POSIX_SPAWN_CLOEXEC_DEFAULT does this for us.
  int sourceFileDescriptor = attachment.fileDescriptor;
  int status = posix_spawn_file_actions_adddup2(fileActions, sourceFileDescriptor, targetFileDescriptor);
  if (status != 0) {
    return [[FBControlCoreError
      describeFormat:@"Failed to dup input %d, to %d: %s", sourceFileDescriptor, targetFileDescriptor, strerror(status)]
      failBool:error];
  }
  return YES;
}

@interface FBTaskProcessPosixSpawn : NSObject <FBLaunchedProcess>

@property (nonatomic, strong, readonly) FBProcessSpawnConfiguration *configuration;
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *statLoc;
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *signal;

@end

@implementation FBTaskProcessPosixSpawn

@synthesize exitCode = _exitCode;
@synthesize processIdentifier = _processIdentifier;

+ (FBFuture<FBTaskProcessPosixSpawn *> *)processWithConfiguration:(FBProcessSpawnConfiguration *)configuration attachment:(FBProcessIOAttachment *)attachment logger:(id<FBControlCoreLogger>)logger
{
  // Convert the arguments to the argv expected by posix_spawn
  NSArray<NSString *> *arguments = configuration.arguments;
  char *argv[arguments.count + 2]; // 0th arg is launch path, last arg is NULL
  argv[0] = (char *) configuration.launchPath.UTF8String;
  argv[arguments.count + 1] = NULL;
  for (NSUInteger index = 0; index < arguments.count; index++) {
    argv[index + 1] = (char *) arguments[index].UTF8String; // Offset by the launch path arg.
  }

  // Convert the environment to the envp expected by posix_spawn
  NSDictionary<NSString *, NSString *> *environment = configuration.environment;
  NSArray<NSString *> *environmentNames = environment.allKeys;
  char *envp[environment.count + 1];
  envp[environment.count] = NULL;
  for (NSUInteger index = 0; index < environmentNames.count; index++) {
    NSString *name = environmentNames[index];
    NSString *value = [NSString stringWithFormat:@"%@=%@", name, environment[name]];
    envp[index] = (char *) value.UTF8String;
  }

  // Convert the file descriptors
  posix_spawn_file_actions_t fileActions;
  posix_spawn_file_actions_init(&fileActions);

  NSError *error = nil;
  if (!AddInputFileActions(&fileActions, attachment.stdIn, STDIN_FILENO, &error)) {
    return [FBFuture futureWithError:error];
  }
  if (!AddOutputFileActions(&fileActions, attachment.stdOut, STDOUT_FILENO, &error)) {
    return [FBFuture futureWithError:error];
  }
  if (!AddOutputFileActions(&fileActions, attachment.stdErr, STDERR_FILENO, &error)) {
    return [FBFuture futureWithError:error];
  }

  // Make the spawn attributes
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
    return [[FBControlCoreError
      describeFormat:@"Failed to launch %@ with error %s", configuration, strerror(status)]
      failFuture];
  }

  FBMutableFuture<NSNumber *> *statLoc = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *exitCode = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *signal = FBMutableFuture.future;
  [self resolveProcessCompletion:processIdentifier statLoc:statLoc exitCode:exitCode signal:signal logger:logger];
  FBTaskProcessPosixSpawn *process = [[self alloc] initWithProcessIdentifier:processIdentifier statLoc:statLoc exitCode:exitCode signal:signal];
  return [FBFuture futureWithResult:process];
}

+ (void)resolveProcessCompletion:(pid_t)processIdentifier statLoc:(FBMutableFuture<NSNumber *> *)statLoc exitCode:(FBMutableFuture<NSNumber *> *)exitCode signal:(FBMutableFuture<NSNumber *> *)signal logger:(id<FBControlCoreLogger>)logger
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
    if (waitpid(processIdentifier, &status, WNOHANG) == -1) {
      [logger logFormat:@"Failed to get the exit status with waitpid: %s", strerror(errno)];
    }
    // First resolve the statLoc future.
    [statLoc resolveWithResult:@(status)];

    // Then resolve the exitCode & signal future. These are essentially mutually exclusive
    if (WIFSIGNALED(status)) {
      int signalCode = WTERMSIG(status);
      NSError *error = [[FBControlCoreError
        describeFormat:@"No normal exit code, process %d died with signal %d", processIdentifier, signalCode]
        build];
      [exitCode resolveWithError:error];
      [signal resolveWithResult:@(signalCode)];
    } else {
      int exitCodeValue = WEXITSTATUS(status);
      NSError *error = [[FBControlCoreError
        describeFormat:@"Normal exit code, process %d died with exit code %d", processIdentifier, exitCodeValue]
        build];
      [exitCode resolveWithResult:@(exitCodeValue)];
      [signal resolveWithError:error];
    }

    // We only need a single notification and the dispatch_source must be retained until we resolve the future.
    // Cancelling the source at the end will release the source as the event handler will no longer be referenced.
    dispatch_cancel(source);
  });
  dispatch_resume(source);
}

- (instancetype)initWithProcessIdentifier:(pid_t)processIdentifier statLoc:(FBFuture<NSNumber *> *)statLoc exitCode:(FBFuture<NSNumber *> *)exitCode signal:(FBFuture<NSNumber *> *)signal
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processIdentifier = processIdentifier;
  _statLoc = statLoc;
  _exitCode = exitCode;
  _signal = signal;

  return self;
}

- (FBFuture<NSNumber *> *)sendSignal:(int)signo
{
  kill(self.processIdentifier, signo);
  return self.statLoc;
}

@end

@interface FBTask ()

@property (nonatomic, copy, nullable, readonly) NSSet<NSNumber *> *acceptableExitCodes;
@property (nonatomic, strong, readonly) FBProcessIO *io;
@property (nonatomic, strong, readonly) FBTaskProcessPosixSpawn *process;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBTask

@synthesize exitCode = _exitCode;
@synthesize signal = _signal;
@synthesize statLoc = _statLoc;

#pragma mark Initializers

+ (FBFuture<FBTask *> *)startTaskWithConfiguration:(FBProcessSpawnConfiguration *)configuration acceptableExitCodes:(NSSet<NSNumber *> *)acceptableExitCodes logger:(id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.task", DISPATCH_QUEUE_SERIAL);
  return [[[configuration.io
    attach]
    onQueue:queue fmap:^(FBProcessIOAttachment *attachment) {
      // Everything is setup, launch the process now.
      return [FBTaskProcessPosixSpawn processWithConfiguration:configuration attachment:attachment logger:logger];
    }]
    onQueue:queue map:^(FBTaskProcessPosixSpawn *process) {
      return [[self alloc]
        initWithProcess:process
        io:configuration.io
        queue:queue
        acceptableExitCodes:acceptableExitCodes];
    }];
}

- (instancetype)initWithProcess:(FBTaskProcessPosixSpawn *)process io:(FBProcessIO *)io queue:(dispatch_queue_t)queue acceptableExitCodes:(nullable NSSet<NSNumber *> *)acceptableExitCodes
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _process = process;
  _io = io;
  _queue = queue;
  _acceptableExitCodes = acceptableExitCodes;

  // Wrap the underlying FBLaunchedProcess with IO termination before resolution.
  _statLoc = [FBTask onQueue:queue wrapNumberFuture:process.statLoc inTeardownOfIO:io];
  _exitCode = [FBTask onQueue:queue wrapNumberFuture:process.exitCode inTeardownOfIO:io];
  _signal = [FBTask onQueue:queue wrapNumberFuture:process.signal inTeardownOfIO:io];

  // Do not propogate cancellation of completed to the exit code future.
  FBMutableFuture<NSNumber *> *shieldedExitCode = FBMutableFuture.future;
  [shieldedExitCode resolveFromFuture:self.exitCode];
  _completed = [[[shieldedExitCode
  onQueue:self.queue chain:^ FBFuture<NSNumber *> * (FBFuture<NSNumber *> *future) {
      // We have a cancellation responder, so de-duplicate the handling of it.
      if (future.state == FBFutureStateCancelled) {
        return future;
      }
      return [self terminate];
    }]
    named:process.configuration.description]
    onQueue:self.queue respondToCancellation:^{
      // Respond to cancellation in the handler, instead of in chain.
      // This means that the caller can be notified of the full teardown with the value of -[FBFuture cancel]
      return [[self
        terminate]
        onQueue:self.queue chain:^(id _) {
          // Avoid any kind of error in a cancellation handler.
          return FBFuture.empty;
        }];
    }];


  return self;
}

#pragma mark Public Methods

- (FBFuture<NSNumber *> *)sendSignal:(int)signo
{
  return [[FBFuture
    onQueue:self.queue resolve:^{
      return [self.process sendSignal:signo];
    }]
    mapReplace:@(signo)];
}

#pragma mark Accessors

- (pid_t)processIdentifier
{
  return self.process.processIdentifier;
}

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

- (FBFuture<NSNumber *> *)terminate
{
  NSSet<NSNumber *> *acceptableExitCodes = self.acceptableExitCodes;
  return [[[self
    teardownProcess] // Wait for the process to exit, terminating it if necessary.
    onQueue:self.queue chain:^(FBFuture<NSNumber *> *exitCodeFuture) {
      // Then tear-down the resources, this should happen regardless of the exit status.
      return [[self.io detach] chainReplace:exitCodeFuture];
    }]
    onQueue:self.queue fmap:^(NSNumber *exitCode) {
      // If exit codes are defined, check them.
      if (acceptableExitCodes == nil) {
        return [FBFuture futureWithResult:exitCode];
      }
      if ([acceptableExitCodes containsObject:exitCode]) {
        return [FBFuture futureWithResult:exitCode];
      }
      NSString *message = [NSString stringWithFormat:@"Exit Code %@ is not acceptable %@", exitCode, [FBCollectionInformation oneLineDescriptionFromArray:acceptableExitCodes.allObjects]];
      if ([self.stdErr conformsToProtocol:@protocol(FBAccumulatingBuffer)]) {
        NSData *outputData = [self.stdErr data];
        message = [message stringByAppendingFormat:@": %@", [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding]];
      }
      return [[[FBControlCoreError
        describe:message]
        inDomain:FBTaskErrorDomain]
        failFuture];
    }];
}

- (FBFuture<NSNumber *> *)teardownProcess
{
  if (self.process.exitCode.state == FBFutureStateRunning) {
    return [self.process sendSignal:SIGTERM];
  }
  return self.process.exitCode;
}

+ (FBFuture<NSNumber *> *)onQueue:(dispatch_queue_t)queue wrapNumberFuture:(FBFuture<NSNumber *> *)future inTeardownOfIO:(FBProcessIO *)io
{
  return [[future
    onQueue:queue chain:^(id _) {
      return [io detach];
    }]
    chainReplace:future];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString
    stringWithFormat:@"%@ | State %@",
    self.process.configuration.description,
    self.completed
  ];
}

@end
