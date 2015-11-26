/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessQuery.h"

#include <libproc.h>
#include <limits.h>
#include <sys/sysctl.h>

#import "FBProcessInfo+Private.h"
#import "FBProcessInfo.h"

#define PID_MAX 99999

#pragma mark Calling libproc

typedef BOOL(^ProcessIterator)(pid_t pid);
typedef size_t(^LibProcCaller)(void);

static void IterateWith(pid_t *pidBuffer, size_t pidBufferSize, ProcessIterator iterator, LibProcCaller caller)
{
  size_t actualSize = caller();
  if (actualSize < 1) {
    return;
  }

  for (pid_t index = 0; index < actualSize; index++) {
    pid_t processIdentifier = *(pidBuffer + index);
    if (!iterator(processIdentifier)) {
      break;
    }
  }
}

static void IterateAllProcesses(pid_t *pidBuffer, size_t pidBufferSize, ProcessIterator iterator)
{
  IterateWith(pidBuffer, pidBufferSize, iterator, ^ size_t () {
    return proc_listallpids(pidBuffer, pidBufferSize);
  });
}

static void IterateSubprocessesOf(pid_t *pidBuffer, size_t pidBufferSize, pid_t parent, ProcessIterator iterator)
{
  IterateWith(pidBuffer, pidBufferSize, iterator, ^ size_t () {
    return proc_listchildpids(parent, pidBuffer, pidBufferSize);
  });
}

static void IterateOpenFiles(pid_t *pidBuffer, size_t pidBufferSize, const char *path, ProcessIterator iterator)
{
  IterateWith(pidBuffer, pidBufferSize,iterator, ^ size_t () {
    return proc_listpidspath(
      PROC_LISTPIDSPATH_PATH_IS_VOLUME,
      PROC_ALL_PIDS,
      path,
      0,
      pidBuffer,
      pidBufferSize
    );
  });
}

static inline FBFoundProcess *ProcessInfoForProcessIdentifier(pid_t processIdentifier, char *buffer, size_t bufferSize)
{
  // Much of the layout information here comes from libtop.c in Apple's top(1) Open Source implementation.
  int name[3] = {CTL_KERN, KERN_PROCARGS2, processIdentifier};

  size_t actualSize = bufferSize;
  if (sysctl(name, 3, buffer, &actualSize, NULL, 0) == -1) {
    return nil;
  }
  if (actualSize == 0) {
    return nil;
  }

  // First Position is argc.
  const char *startPosition = buffer;
  const int argc = *startPosition;

  // If argc isn't 1 or more, something is wrong
  if (argc < 1) {
    return nil;
  }

  // launch path starts above argc
  char *currentPosition = (char *) startPosition + sizeof(int);
  NSString *launchPath = [[NSString alloc] initWithCString:currentPosition encoding:NSASCIIStringEncoding];
  currentPosition += strlen(currentPosition);
  currentPosition += 1;

  // Move through the padding to get to the the argv
  while (*currentPosition == '\0') {
    currentPosition++;
  }

  // Enumerate up to the value of argc
  NSMutableArray *arguments = [NSMutableArray array];
  for (int index = 0; index < argc; index++) {
    // Create Objective-C String from current position.
    NSString *argument = [[NSString alloc] initWithCString:currentPosition encoding:NSASCIIStringEncoding];
    [arguments addObject:argument];

    // Move the current string position passed the null-character.
    currentPosition += strlen(currentPosition);
    currentPosition += 1;
  }

  // Now the environment is here
  NSMutableDictionary *environment = [NSMutableDictionary dictionary];
  while (currentPosition != '\0') {
    NSString *string = [[NSString alloc] initWithCString:currentPosition encoding:NSASCIIStringEncoding];
    NSArray *tokens = [string componentsSeparatedByString:@"="];
    // If we don't get 2 tokens, something is malformed.
    if (tokens.count != 2) {
      break;
    }
    environment[tokens[0]] = tokens[1];

    // Move the current string position passed the null-character.
    currentPosition += strlen(currentPosition);
    currentPosition += 1;
  }

  FBFoundProcess *process = [FBFoundProcess new];
  process.launchPath = launchPath;
  process.processIdentifier = processIdentifier;
  process.arguments = [arguments copy];
  process.environment = [environment copy];

  return process;
}

static inline BOOL ProcInfoForProcessIdentifier(pid_t processIdentifier, struct kinfo_proc* procOut)
{
  size_t size = sizeof(struct kinfo_proc);
  int name[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, processIdentifier };
  if (sysctl(name, 4, procOut, &size, NULL, 0) == -1) {
    return NO;
  }

  return YES;
}

@interface FBProcessQuery ()

@property (nonatomic, assign, readonly) size_t argumentBufferSize;
@property (nonatomic, assign, readonly) char *argumentBuffer;

@property (nonatomic, assign, readonly) size_t pidBufferSize;
@property (nonatomic, assign, readonly) pid_t *pidBuffer;


@end

@implementation FBProcessQuery

#pragma mark Lifecycle

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _argumentBufferSize = sizeof(char) * ARG_MAX;
  _argumentBuffer = malloc(_argumentBufferSize);

  _pidBufferSize = sizeof(pid_t) * PID_MAX;
  _pidBuffer = malloc(_pidBufferSize);

  return self;
}

- (void)dealloc
{
  free(_argumentBuffer);
  free(_pidBuffer);
}

#pragma mark Queries

- (id<FBProcessInfo>)processInfoFor:(pid_t)processIdentifier
{
  return ProcessInfoForProcessIdentifier(
    processIdentifier,
    self.argumentBuffer,
    self.argumentBufferSize
  );
}

- (NSArray *)subprocessesOf:(pid_t)parent
{
  NSMutableArray *subprocesses = [NSMutableArray array];

  IterateSubprocessesOf(self.pidBuffer, self.pidBufferSize, parent, ^ BOOL (pid_t pid) {
    id<FBProcessInfo> info = [self processInfoFor:pid];
    if (info) {
      [subprocesses addObject:info];
    }
    return YES;
  });

  return [subprocesses copy];
}

- (NSArray *)processesWithLaunchPathSubstring:(NSString *)substring
{
  NSMutableArray *subprocesses = [NSMutableArray array];

  IterateAllProcesses(self.pidBuffer, self.pidBufferSize, ^ BOOL (pid_t pid) {
    id<FBProcessInfo> info = [self processInfoFor:pid];
    if ([info.launchPath containsString:substring]) {
      [subprocesses addObject:info];
    }
    return YES;
  });

  return [subprocesses copy];
}

- (pid_t)subprocessOf:(pid_t)parent withName:(NSString *)needleString
{
  __block pid_t foundProcess = -1;
  size_t argumentBufferSize = self.argumentBufferSize;
  char *argumentBuffer = self.argumentBuffer;
  const char *needle = needleString.UTF8String;

  IterateSubprocessesOf(self.pidBuffer, self.pidBufferSize, parent, ^ BOOL (pid_t pid) {
    if (proc_name(pid, argumentBuffer, argumentBufferSize) == -1) {
      return YES;
    }
    if (strstr(argumentBuffer, needle) == NULL) {
      return YES;
    }

    foundProcess = pid;
    return NO;
  });

  return foundProcess;
}

- (pid_t)processWithOpenFileTo:(const char *)filename
{
  __block pid_t processIdentifier = -1;
  IterateOpenFiles(self.pidBuffer, self.pidBufferSize, filename, ^ BOOL (pid_t pid) {
    processIdentifier = pid;
    return NO;
  });;
  return processIdentifier;
}

- (pid_t)parentOf:(pid_t)child
{
  struct kinfo_proc proc;
  if (!ProcInfoForProcessIdentifier(child, &proc)) {
    return -1;
  }
  return proc.kp_eproc.e_ppid;
}

@end
