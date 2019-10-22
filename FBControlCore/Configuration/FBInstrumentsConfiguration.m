/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBInstrumentsConfiguration.h"

#import "FBCollectionInformation.h"

@implementation FBInstrumentsTimings

#pragma mark Initializers

+ (instancetype)timingsWithTerminateTimeout:(NSTimeInterval)terminateTimeout launchRetryTimeout:(NSTimeInterval)launchRetryTimeout launchErrorTimeout:(NSTimeInterval)launchErrorTimeout operationDuration:(NSTimeInterval)operationDuration
{
  return [[self alloc] initWithterminateTimeout:terminateTimeout launchRetryTimeout:launchRetryTimeout launchErrorTimeout:launchErrorTimeout operationDuration:operationDuration];
}

- (instancetype)initWithterminateTimeout:(NSTimeInterval)terminateTimeout launchRetryTimeout:(NSTimeInterval)launchRetryTimeout launchErrorTimeout:(NSTimeInterval)launchErrorTimeout operationDuration:(NSTimeInterval)operationDuration
{
  self = [self init];
  if (!self) {
    return nil;
  }

  _terminateTimeout = terminateTimeout;
  _launchRetryTimeout = launchRetryTimeout;
  _launchErrorTimeout = launchErrorTimeout;
  _operationDuration = operationDuration;

  return self;
}

@end

@implementation FBInstrumentsConfiguration

#pragma mark Initializers

+ (instancetype)configurationWithInstrumentName:(NSString *)instrumentName targetApplication:(NSString *)targetApplication environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments timings:(FBInstrumentsTimings *)timings
{
  return [[self alloc] initWithInstrumentName:instrumentName targetApplication:targetApplication environment:environment arguments:arguments timings:timings];
}

- (instancetype)initWithInstrumentName:(NSString *)instrumentName targetApplication:(NSString *)targetApplication environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments timings:(FBInstrumentsTimings *)timings
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _instrumentName = instrumentName;
  _targetApplication = targetApplication;
  _environment = environment;
  _arguments = arguments;
  _timings = timings;
  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Instrument %@ | %@ | %@ | %@ | duration %f | terminate timeout %f | launch retry timeout %f | launch error timeout %f",
    self.instrumentName,
    self.targetApplication,
    [FBCollectionInformation oneLineDescriptionFromDictionary:self.environment],
    [FBCollectionInformation oneLineDescriptionFromArray:self.arguments],
    self.timings.operationDuration,
    self.timings.terminateTimeout,
    self.timings.launchRetryTimeout,
    self.timings.launchErrorTimeout
  ];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

@end
