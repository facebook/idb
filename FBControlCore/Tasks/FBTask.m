/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTask.h"

#include <spawn.h>

#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBDataBuffer.h"
#import "FBDataConsumer.h"
#import "FBFileWriter.h"
#import "FBLaunchedProcess.h"
#import "FBProcessIO.h"
#import "FBProcessStream.h"
#import "FBTaskConfiguration.h"

NSString *const FBTaskErrorDomain = @"com.facebook.FBControlCore.task";

/**
 A protocol for abstracting over implementations of subprocesses.
 */
@protocol FBTaskProcess <NSObject, FBLaunchedProcess>

/**
 The designated initializer

 @param configuration the configuration of the task.
 @param io the io attachment.
 @return a new FBTaskProcess Instance.
 */
+ (FBFuture<id<FBTaskProcess>> *)processWithConfiguration:(FBTaskConfiguration *)configuration io:(FBProcessIOAttachment *)io;

/**
 Send a signal to the process.
 Returns a future with the resolved exit code of the process.
 */
- (FBFuture<NSNumber *> *)sendSignal:(int)signo;

@end

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

@interface FBTaskProcess_PosixSpawn : NSObject <FBTaskProcess>

@property (nonatomic, strong, readonly) FBTaskConfiguration *configuration;
@property (nonatomic, strong, nullable, readwrite) id stdIn;
@property (nonatomic, strong, nullable, readwrite) id stdOut;
@property (nonatomic, strong, nullable, readwrite) id stdErr;

@end

@implementation FBTaskProcess_PosixSpawn

@synthesize exitCode = _exitCode;
@synthesize processIdentifier = _processIdentifier;

+ (FBFuture<id<FBTaskProcess>> *)processWithConfiguration:(FBTaskConfiguration *)configuration io:(FBProcessIOAttachment *)io
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
  if (!AddInputFileActions(&fileActions, io.stdIn, STDIN_FILENO, &error)) {
    return [FBFuture futureWithError:error];
  }
  if (!AddOutputFileActions(&fileActions, io.stdOut, STDOUT_FILENO, &error)) {
    return [FBFuture futureWithError:error];
  }
  if (!AddOutputFileActions(&fileActions, io.stdErr, STDERR_FILENO, &error)) {
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

  FBFuture<NSNumber *> *exitCode = [self exitCodeFutureForProcessIdentifier:processIdentifier logger:configuration.logger];
  id<FBTaskProcess> process = [[self alloc] initWithProcessIdentifier:processIdentifier exitCode:exitCode];
  return [FBFuture futureWithResult:process];
}

+ (FBFuture<NSNumber *> *)exitCodeFutureForProcessIdentifier:(pid_t)processIdentifier logger:(id<FBControlCoreLogger>)logger
{
  FBMutableFuture<NSNumber *> *exitCode = FBMutableFuture.future;
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
    if (WIFEXITED(status)) {
      [exitCode resolveWithResult:@(WEXITSTATUS(status))];
    } else if (WIFSIGNALED(status)) {
      [exitCode resolveWithResult:@(WTERMSIG(status))];
    } else {
      [exitCode resolveWithResult:@(status)];
    }
    // We only need a single notification and the dispatch_source must be retained until we resolve the future.
    // Cancelling the source at the end will release the source as the event handler will no longer be referenced.
    dispatch_cancel(source);
  });
  dispatch_resume(source);
  return exitCode;
}

- (instancetype)initWithProcessIdentifier:(pid_t)processIdentifier exitCode:(FBFuture<NSNumber *> *)exitCode
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processIdentifier = processIdentifier;
  _exitCode = exitCode;

  return self;
}

- (FBFuture<NSNumber *> *)sendSignal:(int)signo
{
  kill(self.processIdentifier, signo);
  return self.exitCode;
}

@end

@interface FBTask ()

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, copy, readonly) NSSet<NSNumber *> *acceptableStatusCodes;
@property (nonatomic, copy, readonly) NSString *configurationDescription;
@property (nonatomic, copy, readonly) NSString *programName;

@property (nonatomic, strong, readwrite) id<FBTaskProcess> process;
@property (nonatomic, strong, nullable, readwrite) FBProcessIO *io;

@end

@implementation FBTask

#pragma mark Initializers

+ (FBFuture<FBTask *> *)startTaskWithConfiguration:(FBTaskConfiguration *)configuration
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.task", DISPATCH_QUEUE_SERIAL);
  return [[[configuration.io
    attach]
    onQueue:queue fmap:^(FBProcessIOAttachment *attachment) {
      // Everything is setup, launch the process now.
      return [FBTaskProcess_PosixSpawn processWithConfiguration:configuration io:attachment];
    }]
    onQueue:queue map:^(id<FBTaskProcess> process) {
      return [[self alloc]
        initWithProcess:process
        io:configuration.io
        queue:queue
        acceptableStatusCodes:configuration.acceptableStatusCodes
        configurationDescription:configuration.description
        programName:configuration.programName];
    }];
}

- (instancetype)initWithProcess:(id<FBTaskProcess>)process io:(FBProcessIO *)io queue:(dispatch_queue_t)queue acceptableStatusCodes:(NSSet<NSNumber *> *)acceptableStatusCodes configurationDescription:(NSString *)configurationDescription programName:(NSString *)programName
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _process = process;
  _acceptableStatusCodes = acceptableStatusCodes;
  _io = io;
  _queue = queue;
  _configurationDescription = configurationDescription;
  _programName = programName;

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
    named:self.configurationDescription]
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

- (FBFuture<NSNumber *> *)exitCode
{
  return self.process.exitCode;
}

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
  return [[[self
    teardownProcess] // Wait for the process to exit, terminating it if necessary.
    onQueue:self.queue chain:^(FBFuture<NSNumber *> *exitCodeFuture) {
      // Then tear-down the resources, this should happen regardless of the exit status.
      return [[self.io detach] chainReplace:exitCodeFuture];
    }]
    onQueue:self.queue fmap:^(NSNumber *exitCode) {
      // Then check whether the exit code honours the acceptable codes.
      if (![self.acceptableStatusCodes containsObject:exitCode]) {
        NSString *message = [NSString stringWithFormat:@"%@ Returned non-zero status code %@", self.programName, exitCode];
        if ([self.stdErr conformsToProtocol:@protocol(FBAccumulatingBuffer)]) {
          NSData *outputData = [self.stdErr data];
          message = [message stringByAppendingFormat:@": %@", [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding]];
        }
        return [[[FBControlCoreError
          describe:message]
          inDomain:FBTaskErrorDomain]
          failFuture];
      }
      return [FBFuture futureWithResult:exitCode];
    }];
}

- (FBFuture<NSNumber *> *)teardownProcess
{
  if (self.process.exitCode.state == FBFutureStateRunning) {
    return [self.process sendSignal:SIGTERM];
  }
  return self.process.exitCode;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString
    stringWithFormat:@"%@ | State %@",
    self.configurationDescription,
    self.completed
  ];
}

@end
