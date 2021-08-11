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
#import "FBProcessSpawnCommands.h"
#import "FBProcessIO.h"
#import "FBProcessSpawnConfiguration.h"
#import "FBProcessStream.h"

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

@synthesize configuration = _configuration;
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
  [logger logFormat:@"%@ Launched with pid %d", configuration.processName, processIdentifier];

  FBMutableFuture<NSNumber *> *statLoc = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *exitCode = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *signal = FBMutableFuture.future;
  [self resolveProcessCompletion:processIdentifier attachment:attachment statLoc:statLoc exitCode:exitCode signal:signal configuration:configuration logger:logger];
  FBTaskProcessPosixSpawn *process = [[self alloc] initWithConfiguration:configuration processIdentifier:processIdentifier statLoc:statLoc exitCode:exitCode signal:signal];
  return [FBFuture futureWithResult:process];
}

+ (void)resolveProcessCompletion:(pid_t)processIdentifier attachment:(FBProcessIOAttachment *)attachment statLoc:(FBMutableFuture<NSNumber *> *)statLoc exitCode:(FBMutableFuture<NSNumber *> *)exitCode signal:(FBMutableFuture<NSNumber *> *)signal configuration:(FBProcessSpawnConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
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
    
    // Resolve all of the related process finshed futures now, so that they do not need asynchronous resolution.
    [FBProcessSpawnCommandHelpers
      resolveProcessFinishedWithStatLoc:status
      inTeardownOfIOAttachment:attachment
      statLocFuture:statLoc
      exitCodeFuture:exitCode
      signalFuture:signal
      processIdentifier:processIdentifier
      configuration:configuration
      queue:queue
      logger:logger];

    // We only need a single notification and the dispatch_source must be retained until we resolve the future.
    // Cancelling the source at the end will release the source as the event handler will no longer be referenced.
    dispatch_cancel(source);
  });
  dispatch_resume(source);
}

- (instancetype)initWithConfiguration:(FBProcessSpawnConfiguration *)configuration processIdentifier:(pid_t)processIdentifier statLoc:(FBFuture<NSNumber *> *)statLoc exitCode:(FBFuture<NSNumber *> *)exitCode signal:(FBFuture<NSNumber *> *)signal
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _processIdentifier = processIdentifier;
  _statLoc = statLoc;
  _exitCode = exitCode;
  _signal = signal;

  return self;
}

- (FBFuture<NSNumber *> *)exitedWithCodes:(NSSet<NSNumber *> *)exitCodes
{
  return [FBProcessSpawnCommandHelpers exitedWithCode:self.exitCode isAcceptable:exitCodes];
}

- (FBFuture<NSNumber *> *)sendSignal:(int)signo
{
  return [FBProcessSpawnCommandHelpers sendSignal:signo toProcess:self];
}

- (FBFuture<NSNumber *> *)sendSignal:(int)signo backingOffToKillWithTimeout:(NSTimeInterval)timeout logger:(id<FBControlCoreLogger>)logger
{
  return [FBProcessSpawnCommandHelpers sendSignal:signo backingOffToKillWithTimeout:timeout toProcess:self logger:logger];
}

@end

@interface FBTask ()

@property (nonatomic, strong, readonly) FBProcessIOAttachment *attachment;
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
  return [[configuration.io
    attach]
    onQueue:queue fmap:^(FBProcessIOAttachment *attachment) {
      // Everything is setup, launch the process now.
      return [[FBTaskProcessPosixSpawn
        processWithConfiguration:configuration attachment:attachment logger:logger]
        onQueue:queue map:^(FBTaskProcessPosixSpawn *process) {
          return [[self alloc]
            initWithProcess:process
            queue:queue
            acceptableExitCodes:acceptableExitCodes
            logger:logger];
        }];
    }];
}

- (instancetype)initWithProcess:(FBTaskProcessPosixSpawn *)process queue:(dispatch_queue_t)queue acceptableExitCodes:(NSSet<NSNumber *> *)acceptableExitCodes logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _process = process;
  _queue = queue;

  // The IO Teardown and Sequencing is priced-in the pass from above.
  _statLoc = process.statLoc;
  _exitCode = process.exitCode;
  _signal = process.signal;

  // Do not propogate cancellation of completed to the exit code future.
  // Never cancel the underlying statLoc future. We can layer the cancellation and exit code checking semantics on top.
  FBMutableFuture<NSNumber *> *shieldedProcessFinished = FBMutableFuture.future;
  [shieldedProcessFinished resolveFromFuture:self.statLoc];
  _completed = [[[shieldedProcessFinished
    onQueue:self.queue respondToCancellation:^{
      return [self sendSignal:SIGTERM];
    }]
    chainReplace:self.exitCode]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (NSNumber *exitCode) {
      return [FBProcessSpawnCommandHelpers confirmExitCode:exitCode.intValue isAcceptable:acceptableExitCodes];
    }];

  return self;
}

#pragma mark - FBLaunchedProcess

#pragma mark Public

- (FBFuture<NSNumber *> *)exitedWithCodes:(NSSet<NSNumber *> *)exitCodes
{
  return [self.process exitedWithCodes:exitCodes];
}

- (FBFuture<NSNumber *> *)sendSignal:(int)signo
{
  return [self.process sendSignal:signo];
}

- (FBFuture<NSNumber *> *)sendSignal:(int)signo backingOffToKillWithTimeout:(NSTimeInterval)timeout logger:(id<FBControlCoreLogger>)logger
{
  return [self.process sendSignal:signo backingOffToKillWithTimeout:timeout logger:logger];
}

#pragma mark Accessors

- (FBProcessSpawnConfiguration *)configuration
{
  return self.process.configuration;
}

- (pid_t)processIdentifier
{
  return self.process.processIdentifier;
}

- (nullable id)stdIn
{
  return [self.process.configuration.io.stdIn contents];
}

- (nullable id)stdOut
{
  return [self.process.configuration.io.stdOut contents];
}

- (nullable id)stdErr
{
  return [self.process.configuration.io.stdErr contents];
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
