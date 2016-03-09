/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorHistory.h"
#import "FBSimulatorHistory+Private.h"

#import "FBProcessLaunchConfiguration.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulatorApplication.h"

NSString *const FBSimulatorHistoryDiagnosticNameTerminationStatus = @"termination_status";

@implementation FBSimulatorHistory

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _timestamp = [NSDate date];
  _mutableLaunchedProcesses = [NSMutableOrderedSet orderedSet];
  _mutableProcessLaunchConfigurations = [NSMutableDictionary dictionary];
  _mutableProcessMetadata = [NSMutableDictionary dictionary];

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBSimulatorHistory *history = [self.class new];
  history.timestamp = self.timestamp;
  history.simulatorState = self.simulatorState;
  history.previousState = self.previousState;
  history.mutableLaunchedProcesses = [self.mutableLaunchedProcesses mutableCopy];
  history.mutableProcessLaunchConfigurations = [self.mutableProcessLaunchConfigurations mutableCopy];
  history.mutableProcessMetadata = [self.mutableProcessMetadata mutableCopy];
  return history;
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _timestamp = [coder decodeObjectForKey:NSStringFromSelector(@selector(timestamp))];
  _simulatorState = (FBSimulatorState) [[coder decodeObjectForKey:NSStringFromSelector(@selector(simulatorState))] unsignedIntegerValue];
  _previousState = [coder decodeObjectForKey:NSStringFromSelector(@selector(previousState))];
  _mutableLaunchedProcesses = [[coder decodeObjectForKey:NSStringFromSelector(@selector(mutableLaunchedProcesses))] mutableCopy];
  _mutableProcessLaunchConfigurations = [[coder decodeObjectForKey:NSStringFromSelector(@selector(mutableProcessLaunchConfigurations))] mutableCopy];
  _mutableProcessMetadata = [[coder decodeObjectForKey:NSStringFromSelector(@selector(mutableProcessMetadata))] mutableCopy];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.timestamp forKey:NSStringFromSelector(@selector(timestamp))];
  [coder encodeObject:@(self.simulatorState) forKey:NSStringFromSelector(@selector(simulatorState))];
  [coder encodeObject:self.previousState forKey:NSStringFromSelector(@selector(previousState))];
  [coder encodeObject:self.mutableLaunchedProcesses forKey:NSStringFromSelector(@selector(mutableLaunchedProcesses))];
  [coder encodeObject:self.mutableProcessLaunchConfigurations forKey:NSStringFromSelector(@selector(mutableProcessLaunchConfigurations))];
  [coder encodeObject:self.mutableProcessMetadata forKey:NSStringFromSelector(@selector(mutableProcessMetadata))];
}

#pragma mark Accessors

- (NSArray *)launchedProcesses
{
  return self.mutableLaunchedProcesses.array;
}

- (NSDictionary *)processLaunchConfigurations
{
  return [self.mutableProcessLaunchConfigurations copy];
}

- (NSDictionary *)processMetadata
{
  return [self.mutableProcessMetadata copy];
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.timestamp.hash |
         (unsigned long) self.simulatorState |
         self.mutableLaunchedProcesses.hash |
         self.mutableProcessLaunchConfigurations.hash ^
         self.mutableProcessMetadata.hash;
}

- (BOOL)isEqual:(FBSimulatorHistory *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return ((self.previousState == nil && object.previousState == nil) || [self.previousState isEqual:object.previousState]) &&
         [self.timestamp isEqual:object.timestamp] &&
         self.simulatorState == object.simulatorState &&
         [self.mutableLaunchedProcesses isEqualToOrderedSet:object.mutableLaunchedProcesses] &&
         [self.mutableProcessLaunchConfigurations isEqualToDictionary:object.mutableProcessLaunchConfigurations] &&
         [self.mutableProcessMetadata isEqualToDictionary:object.mutableProcessMetadata];
}

#pragma mark Description

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"History -> %@",
    [FBSimulatorHistory describeDifferenceFrom:self.previousState to:self]
  ];
}

- (NSString *)recursiveChangeDescription
{
  NSMutableString *string = [NSMutableString string];
  [self recursiveChangeDescriptionWithMutableString:string];
  return string;
}

- (void)recursiveChangeDescriptionWithMutableString:(NSMutableString *)string
{
  if (self.previousState) {
    [self.previousState recursiveChangeDescriptionWithMutableString:string];
  }
  [string appendFormat:@"%@\n", [FBSimulatorHistory describeDifferenceFrom:self.previousState to:self]];
}

+ (NSString *)describeDifferenceFrom:(FBSimulatorHistory *)from to:(FBSimulatorHistory *)to
{
  if (to && !from) {
    return @"Inital State";
  }
  NSMutableString *string = [NSMutableString stringWithFormat:@"%@ -> ", to.timestamp];
  if (to.simulatorState != from.simulatorState) {
    [string appendFormat:
      @"Simulator State from %@ to %@ | ",
      [FBSimulator stateStringFromSimulatorState:from.simulatorState],
      [FBSimulator stateStringFromSimulatorState:to.simulatorState]
    ];
  }
  if (![to.mutableLaunchedProcesses isEqualToOrderedSet:from.mutableLaunchedProcesses]) {
    [string appendFormat:
      @"Running Processes from %@ to %@ | ",
      [FBCollectionInformation oneLineDescriptionFromArray:from.mutableLaunchedProcesses.array atKeyPath:@"shortDescription"],
      [FBCollectionInformation oneLineDescriptionFromArray:to.mutableLaunchedProcesses.array atKeyPath:@"shortDescription"]
    ];
  }
  if (![to.mutableProcessMetadata isEqualToDictionary:from.mutableProcessMetadata]) {
    [string appendFormat:@"Process Metadata from %@ to %@ | ",
      [FBCollectionInformation oneLineDescriptionFromDictionary:from.mutableProcessMetadata],
      [FBCollectionInformation oneLineDescriptionFromDictionary:to.mutableProcessMetadata]
    ];
  }
  if (string.length == 0) {
    return @"No Changes";
  }
  return string;
}

@end
