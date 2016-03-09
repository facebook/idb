/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBCrashLogInfo.h"

#import <stdio.h>

#import "FBDiagnostic.h"

@implementation FBCrashLogInfo

#pragma mark Initializers

+ (instancetype)fromCrashLogAtPath:(NSString *)path
{
  FILE *file = fopen(path.UTF8String, "r");
  if (!file) {
    return nil;
  }

  // Buffers for the sscanf
  size_t lineSize = sizeof(char) * 1024;
  char *line = malloc(lineSize);
  char value[lineSize];

  // Values that should exist after scanning
  NSString *processName = nil;
  NSString *parentProcessName = nil;
  pid_t processIdentifier = -1;
  pid_t parentProcessIdentifier = -1;

  NSUInteger lineNumber = 0;
  while (lineNumber++ < 20 && getline(&line, &lineSize, file) > 0 && (processIdentifier == -1 || parentProcessIdentifier == -1)) {
    if (sscanf(line, "Process: %s [%d]", value, &processIdentifier) > 0) {
      processName = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
      continue;
    }
    if (sscanf(line, "Parent Process: %s [%d]", value, &parentProcessIdentifier) > 0) {
      parentProcessName = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
      continue;
    }
  }

  free(line);
  fclose(file);
  if (processIdentifier == -1 || parentProcessIdentifier == -1) {
    return nil;
  }

  return [[FBCrashLogInfo alloc]
    initWithPath:path
    processName:processName
    processIdentifier:processIdentifier
    parentProcessName:parentProcessName
    parentProcessIdentifier:parentProcessIdentifier];
}

- (instancetype)initWithPath:(NSString *)path processName:(NSString *)processName processIdentifier:(pid_t)processIdentifer parentProcessName:(NSString *)parentProcessName parentProcessIdentifier:(pid_t)parentProcessIdentifier
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _path = path;
  _processName = processName;
  _processIdentifier = processIdentifer;
  _parentProcessName = parentProcessName;
  _parentProcessIdentifier = parentProcessIdentifier;

  return self;
}

#pragma mark Public

- (FBDiagnostic *)toDiagnostic:(FBDiagnosticBuilder *)builder
{
  return [[[builder
    updateShortName:[NSString stringWithFormat:@"%@_crash", self.processName]]
    updatePath:self.path]
    build];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Crash => Path %@ | Process %@ | pid %d | Parent %@ | ppid %d",
    self.path,
    self.processName,
    self.processIdentifier,
    self.parentProcessName,
    self.parentProcessIdentifier
  ];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc]
    initWithPath:self.path
    processName:self.processName
    processIdentifier:self.processIdentifier
    parentProcessName:self.parentProcessName
    parentProcessIdentifier:self.parentProcessIdentifier];
}

@end
