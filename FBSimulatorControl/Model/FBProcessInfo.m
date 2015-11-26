/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessInfo.h"
#import "FBProcessInfo+Private.h"

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

- (NSArray *)arguments
{
  return self.launchConfiguration.arguments;
}

- (NSDictionary *)environment
{
  return self.launchConfiguration.environment;
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
    @"Launch %@ | PID %d | Launched %@ | Diagnostics %@",
    self.launchConfiguration,
    self.processIdentifier,
    self.launchDate,
    self.diagnostics
  ];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Process %@ | PID %d",
    self.launchConfiguration.shortDescription,
    self.processIdentifier
  ];
}

@end

@implementation FBFoundProcess

@synthesize launchPath = _launchPath;
@synthesize processIdentifier = _processIdentifier;
@synthesize arguments = _arguments;
@synthesize environment = _environment;

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBFoundProcess *process = [self.class new];
  process.processIdentifier = self.processIdentifier;
  process.launchPath = self.launchPath;
  process.arguments = self.arguments;
  process.environment = self.environment;
  return process;
}

- (NSUInteger)hash
{
  return self.processIdentifier | self.launchPath.hash | self.arguments.hash | self.environment.hash;
}

- (BOOL)isEqual:(FBUserLaunchedProcess *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return self.processIdentifier == object.processIdentifier &&
         [self.launchPath isEqualToString:object.launchPath] &&
         [self.arguments isEqualToArray:object.arguments] &&
         [self.environment isEqualToDictionary:object.environment];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Process %@ | PID %d | Arguments %@ | Environment %@",
    self.launchPath,
    self.processIdentifier,
    self.arguments,
    self.environment
  ];
}

@end
