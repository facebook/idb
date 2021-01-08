/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessLaunchConfiguration.h"
#import "FBProcessOutputConfiguration.h"

#import <FBControlCore/FBControlCore.h>

static NSString *const KeyBinary = @"binary";

@implementation FBAgentLaunchConfiguration

+ (instancetype)configurationWithBinary:(FBBinaryDescriptor *)agentBinary arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment output:(FBProcessOutputConfiguration *)output mode:(FBAgentLaunchMode)mode
{
  if (!agentBinary || !arguments || !environment) {
    return nil;
  }
  return [[self alloc] initWithBinary:agentBinary arguments:arguments environment:environment output:output mode:mode];
}
- (instancetype)initWithBinary:(FBBinaryDescriptor *)agentBinary arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment output:(FBProcessOutputConfiguration *)output mode:(FBAgentLaunchMode)mode
{
  self = [super initWithArguments:arguments environment:environment output:output];
  if (!self) {
    return nil;
  }

  _agentBinary = agentBinary;
  _mode = mode;

  return self;
}

#pragma mark Abstract Methods

- (NSString *)launchPath
{
  return self.agentBinary.path;
}

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"Agent Launch | Binary %@ | Arguments %@ | Environment %@ | Output %@",
    self.agentBinary,
    [FBCollectionInformation oneLineDescriptionFromArray:self.arguments],
    [FBCollectionInformation oneLineDescriptionFromDictionary:self.environment],
    self.output
  ];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:@"Agent Launch %@", self.agentBinary.name];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  // Object is immutable.
  return self;
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return [super hash] | self.agentBinary.hash | self.mode;
}

- (BOOL)isEqual:(FBAgentLaunchConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return [self.agentBinary isEqual:object.agentBinary] &&
         [self.arguments isEqual:object.arguments] &&
         [self.environment isEqual:object.environment] &&
         self.mode == object.mode;
}

@end
