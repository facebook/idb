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

#import "FBCollectionDescriptions.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorSession.h"

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
  _mutableSimulatorDiagnostics = [NSMutableDictionary dictionary];
  _mutableProcessDiagnostics = [NSMutableDictionary dictionary];

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
  history.mutableSimulatorDiagnostics = [self.mutableSimulatorDiagnostics mutableCopy];
  history.mutableProcessDiagnostics = [self.mutableProcessDiagnostics mutableCopy];
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
  _mutableSimulatorDiagnostics = [[coder decodeObjectForKey:NSStringFromSelector(@selector(mutableSimulatorDiagnostics))] mutableCopy];
  _mutableProcessDiagnostics = [[coder decodeObjectForKey:NSStringFromSelector(@selector(mutableProcessDiagnostics))] mutableCopy];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.timestamp forKey:NSStringFromSelector(@selector(timestamp))];
  [coder encodeObject:@(self.simulatorState) forKey:NSStringFromSelector(@selector(simulatorState))];
  [coder encodeObject:self.previousState forKey:NSStringFromSelector(@selector(previousState))];
  [coder encodeObject:self.mutableLaunchedProcesses forKey:NSStringFromSelector(@selector(mutableLaunchedProcesses))];
  [coder encodeObject:self.mutableProcessLaunchConfigurations forKey:NSStringFromSelector(@selector(mutableProcessLaunchConfigurations))];
  [coder encodeObject:self.mutableSimulatorDiagnostics forKey:NSStringFromSelector(@selector(mutableSimulatorDiagnostics))];
  [coder encodeObject:self.mutableProcessDiagnostics forKey:NSStringFromSelector(@selector(mutableProcessDiagnostics))];
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

- (NSDictionary *)simulatorDiagnostics
{
  return [self.mutableSimulatorDiagnostics copy];
}

- (NSDictionary *)processDiagnostics
{
  return [self.mutableProcessDiagnostics copy];
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.timestamp.hash |
         (unsigned long) self.simulatorState |
         self.mutableLaunchedProcesses.hash |
         self.mutableProcessLaunchConfigurations.hash ^
         self.mutableSimulatorDiagnostics.hash ^
         self.mutableProcessDiagnostics.hash;
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
         [self.mutableSimulatorDiagnostics isEqualToDictionary:object.mutableProcessDiagnostics] &&
         [self.mutableProcessDiagnostics isEqualToDictionary:object.mutableProcessDiagnostics];
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
      [FBCollectionDescriptions oneLineDescriptionFromArray:from.mutableLaunchedProcesses.array atKeyPath:@"shortDescription"],
      [FBCollectionDescriptions oneLineDescriptionFromArray:to.mutableLaunchedProcesses.array atKeyPath:@"shortDescription"]
    ];
  }
  if (![to.mutableSimulatorDiagnostics isEqualToDictionary:from.mutableSimulatorDiagnostics]) {
    [string appendFormat:@"Simulator Diagnostics from %@ to %@ | ",
      [FBCollectionDescriptions oneLineDescriptionFromDictionary:from.mutableSimulatorDiagnostics],
      [FBCollectionDescriptions oneLineDescriptionFromDictionary:to.mutableSimulatorDiagnostics]
    ];
  }
  if (![to.mutableProcessDiagnostics isEqualToDictionary:from.mutableProcessDiagnostics]) {
    [string appendFormat:@"Process Diagnostics from %@ to %@ | ",
      [FBCollectionDescriptions oneLineDescriptionFromDictionary:from.mutableProcessDiagnostics],
      [FBCollectionDescriptions oneLineDescriptionFromDictionary:to.mutableProcessDiagnostics]
    ];
  }
  if (string.length == 0) {
    return @"No Changes";
  }
  return string;
}

@end
