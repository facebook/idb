/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBPlistModificationStrategy.h"

#import <CoreSimulator/SimDevice.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBPlistModificationStrategy ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBPlistModificationStrategy

+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithSimulator:simulator];
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

- (BOOL)amendRelativeToPath:(NSString *)relativePath error:(NSError **)error amendWithBlock:( void(^)(NSMutableDictionary<NSString *, id> *) )block
{
  FBSimulator *simulator = self.simulator;
  NSString *simulatorRoot = simulator.device.dataPath;
  NSString *path = [simulatorRoot stringByAppendingPathComponent:relativePath];

  NSError *innerError = nil;
  if (![NSFileManager.defaultManager createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&innerError]) {
    return [[[[FBSimulatorError
      describeFormat:@"Could not create intermediate directories for plist modification at %@", path]
      inSimulator:simulator]
      causedBy:innerError]
      failBool:error];
  }
  NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
  block(dictionary);

  if (![dictionary writeToFile:path atomically:YES]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to write plist at path %@", path]
      inSimulator:simulator]
      failBool:error];
  }
  return YES;
}

@end
