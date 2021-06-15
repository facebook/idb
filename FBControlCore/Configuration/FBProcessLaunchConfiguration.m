/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessLaunchConfiguration.h"
#import "FBProcessOutputConfiguration.h"

@implementation FBProcessLaunchConfiguration

#pragma mark Initializers

- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment output:(FBProcessOutputConfiguration *)output
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _arguments = arguments;
  _environment = environment;
  _output = output;

  return self;
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.arguments.hash ^ (self.environment.hash & self.output.hash);
}

- (BOOL)isEqual:(FBProcessLaunchConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return [self.arguments isEqual:object.arguments] &&
         [self.environment isEqual:object.environment] &&
         [self.output isEqual:object.output];
}

@end
