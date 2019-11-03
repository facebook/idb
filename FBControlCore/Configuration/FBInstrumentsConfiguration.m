/*
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

+ (instancetype)configurationWithTemplateName:(NSString *)templateName targetApplication:(NSString *)targetApplication appEnvironment:(NSDictionary<NSString *, NSString *> *)appEnvironment appArguments:(NSArray<NSString *> *)appArguments toolArguments:(NSArray<NSString *> *)toolArguments timings:(FBInstrumentsTimings *)timings
{
  return [[self alloc] initWithTemplateName:templateName targetApplication:targetApplication appEnvironment:appEnvironment appArguments:appArguments toolArguments:toolArguments timings:timings];
}

- (instancetype)initWithTemplateName:(NSString *)templateName targetApplication:(NSString *)targetApplication appEnvironment:(NSDictionary<NSString *, NSString *> *)appEnvironment appArguments:(NSArray<NSString *> *)appArguments toolArguments:(NSArray<NSString *> *)toolArguments timings:(FBInstrumentsTimings *)timings
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _templateName = templateName;
  _targetApplication = targetApplication;
  _appEnvironment = appEnvironment;
  _appArguments = appArguments;
  _toolArguments = toolArguments;
  _timings = timings;
  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Instruments %@ | %@ | %@ | %@ | %@ | duration %f | terminate timeout %f | launch retry timeout %f | launch error timeout %f",
    self.templateName,
    self.targetApplication,
    [FBCollectionInformation oneLineDescriptionFromDictionary:self.appEnvironment],
    [FBCollectionInformation oneLineDescriptionFromArray:self.appArguments],
    [FBCollectionInformation oneLineDescriptionFromArray:self.toolArguments],
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
