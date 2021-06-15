/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessLaunchConfiguration.h"
#import "FBProcessOutputConfiguration.h"

#import <FBControlCore/FBControlCore.h>

@implementation FBAgentLaunchConfiguration

- (instancetype)initWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment output:(FBProcessOutputConfiguration *)output mode:(FBAgentLaunchMode)mode
{
  self = [super initWithArguments:arguments environment:environment output:output];
  if (!self) {
    return nil;
  }

  _launchPath = launchPath;
  _mode = mode;

  return self;
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return [super hash] | self.launchPath.hash | self.mode;
}

- (BOOL)isEqual:(FBAgentLaunchConfiguration *)object
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
    @"Agent Launch | Binary %@ | Arguments %@ | Environment %@ | Output %@",
    self.launchPath,
    [FBCollectionInformation oneLineDescriptionFromArray:self.arguments],
    [FBCollectionInformation oneLineDescriptionFromDictionary:self.environment],
    self.output
  ];
}

@end
