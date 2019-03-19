/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBInstrumentsConfiguration.h"

#import "FBCollectionInformation.h"

@implementation FBInstrumentsConfiguration

#pragma mark Initializers

+ (instancetype)configurationWithInstrumentName:(NSString *)instrumentName targetApplication:(NSString *)targetApplication environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments duration:(NSTimeInterval)duration
{
  return [[self alloc] initWithInstrumentName:instrumentName targetApplication:targetApplication environment:environment arguments:arguments duration:duration];
}

- (instancetype)initWithInstrumentName:(NSString *)instrumentName targetApplication:(NSString *)targetApplication environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments duration:(NSTimeInterval)duration
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _instrumentName = instrumentName;
  _targetApplication = targetApplication;
  _environment = environment;
  _arguments = arguments;
  _duration = duration;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Instrument %@ | %@ | %@ | %@ | %f",
    self.instrumentName,
    self.targetApplication,
    [FBCollectionInformation oneLineDescriptionFromDictionary:self.environment],
    [FBCollectionInformation oneLineDescriptionFromArray:self.arguments],
    self.duration
  ];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

@end
