/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorProcess.h"
#import "FBSimulatorProcess+Private.h"

#import "FBProcessLaunchConfiguration.h"

@implementation FBUserLaunchedProcess

@synthesize processIdentifier = _processIdentifier;

- (NSString *)launchPath
{
  return self.launchConfiguration.launchPath;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBUserLaunchedProcess *state = [self.class new];
  state.processIdentifier = self.processIdentifier;
  state.launchConfiguration = self.launchConfiguration;
  state.launchDate = self.launchDate;
  state.diagnostics = self.diagnostics;
  return state;
}

- (NSUInteger)hash
{
  return self.processIdentifier | self.launchConfiguration.hash | self.launchConfiguration.hash | self.diagnostics.hash;
}

- (BOOL)isEqual:(FBUserLaunchedProcess *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return self.processIdentifier == object.processIdentifier &&
        [self.launchConfiguration isEqual:object.launchConfiguration] &&
        [self.launchDate isEqual:object.launchDate] &&
        [self.diagnostics isEqual:object.diagnostics];
}

- (NSString *)description
{
  return [self shortDescription];
}

- (NSString *)longDescription
{
  return [NSString stringWithFormat:
    @"Launch %@ | PID %ld | Launched %@ | Diagnostics %@",
    self.launchConfiguration,
    self.processIdentifier,
    self.launchDate,
    self.diagnostics
  ];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Process %@ | PID %ld",
    self.launchConfiguration.shortDescription,
    self.processIdentifier
  ];
}

@end

@implementation FBFoundProcess

@synthesize launchPath = _launchPath;
@synthesize processIdentifier = _processIdentifier;

+ (instancetype)withProcessIdentifier:(NSInteger)processIdentifier launchPath:(NSString *)launchPath
{
  FBFoundProcess *process = [self new];
  process.processIdentifier = processIdentifier;
  process.launchPath = launchPath;
  return process;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [FBFoundProcess withProcessIdentifier:self.processIdentifier launchPath:self.launchPath];
}

- (NSUInteger)hash
{
  return self.processIdentifier | self.launchPath.hash;
}

- (BOOL)isEqual:(FBUserLaunchedProcess *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return self.processIdentifier == object.processIdentifier &&
         [self.launchPath isEqual:object.launchPath];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Process %@ | PID %ld",
    self.launchPath,
    self.processIdentifier
  ];
}

@end
