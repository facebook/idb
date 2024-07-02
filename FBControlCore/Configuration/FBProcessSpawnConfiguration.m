/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessLaunchConfiguration.h"

#import <FBControlCore/FBControlCore.h>

@implementation FBProcessSpawnConfiguration

- (instancetype)initWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment io:(FBProcessIO *)io mode:(FBProcessSpawnMode)mode;
{
  self = [super initWithArguments:arguments environment:environment io:io];
  if (!self) {
    return nil;
  }

  _launchPath = launchPath;
  _mode = mode;

  return self;
}

- (NSString *)processName
{
  return self.launchPath.lastPathComponent;
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return [super hash] | self.launchPath.hash | self.mode;
}

- (BOOL)isEqual:(FBProcessSpawnConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return [self.launchPath isEqual:object.launchPath] &&
         [self.arguments isEqual:object.arguments] &&
         [self.environment isEqual:object.environment] &&
         self.mode == object.mode;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Process Launch %@ | Arguments %@ | Environment %@ | Output %@",
    self.launchPath,
    [FBCollectionInformation oneLineDescriptionFromArray:self.arguments],
    [FBCollectionInformation oneLineDescriptionFromDictionary:self.environment],
    self.io
  ];
}

@end
