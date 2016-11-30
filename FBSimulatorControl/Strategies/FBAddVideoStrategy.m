/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBAddVideoStrategy.h"

#import <CoreSimulator/SimDevice.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBAddVideoPolyfill.h"

@interface FBAddVideoStrategy ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@interface FBAddVideoStrategy_CoreSimulator : FBAddVideoStrategy

@end

@interface FBAddVideoStrategy_Polyfill : FBAddVideoStrategy

@end

@implementation FBAddVideoStrategy

+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator
{
  Class strategyClass = [simulator.device respondsToSelector:@selector(addVideo:error:)]
    ? FBAddVideoStrategy_CoreSimulator.class
    : FBAddVideoStrategy_Polyfill.class;

  return [[strategyClass alloc] initWithSimulator:simulator];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  return self;
}

- (BOOL)addVideos:(NSArray<NSString *> *)paths error:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
}

@end

@implementation FBAddVideoStrategy_CoreSimulator

- (BOOL)addVideos:(NSArray<NSString *> *)paths error:(NSError **)error
{
  for (NSString *path in paths) {
    NSURL *url = [NSURL fileURLWithPath:path];
    NSError *innerError = nil;
    if (![self.simulator.device addVideo:url error:&innerError]) {
      return [[[FBSimulatorError
        describeFormat:@"Failed to upload video at path %@", path]
        causedBy:innerError]
        failBool:error];
    }
  }
  return YES;
}

@end

@implementation FBAddVideoStrategy_Polyfill

- (BOOL)addVideos:(NSArray<NSString *> *)paths error:(NSError **)error
{
  return [[FBAddVideoPolyfill withSimulator:self.simulator] addVideos:paths error:error];
}

@end
