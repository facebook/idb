/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessLaunchConfiguration.h"
#import "FBProcessLaunchConfiguration+Private.h"

#import "FBSimulator.h"
#import "FBSimulatorApplication.h"

@implementation FBProcessLaunchConfiguration

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBProcessLaunchConfiguration *configuration = [self.class new];
  configuration.arguments = self.arguments;
  configuration.environment = self.environment;
  configuration.stdOutPath = self.stdOutPath;
  configuration.stdErrPath = self.stdErrPath;
  return configuration;
}

- (NSUInteger)hash
{
  return self.arguments.hash | self.environment.hash | self.stdErrPath.hash | self.stdOutPath.hash;
}

- (BOOL)isEqual:(FBProcessLaunchConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return [self.arguments isEqual:object.arguments] &&
  [self.environment isEqual:object.environment] &&
  ((self.stdErrPath == nil && object.stdErrPath == nil)  || [self.stdErrPath isEqual:object.stdErrPath]) &&
  ((self.stdOutPath == nil && object.stdOutPath == nil)  || [self.stdOutPath isEqual:object.stdOutPath]);
}

- (NSString *)shortDescription
{
  NSAssert(NO, @"%@ is abstract", NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)longDescription
{
  NSAssert(NO, @"%@ is abstract", NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)launchPath
{
  NSAssert(NO, @"%@ is abstract", NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)description
{
  return [self shortDescription];
}

@end

@implementation FBApplicationLaunchConfiguration

+ (instancetype)configurationWithApplication:(FBSimulatorApplication *)application arguments:(NSArray *)arguments environment:(NSDictionary *)environment
{
  return [self configurationWithApplication:application arguments:arguments environment:environment stdOutPath:nil stdErrPath:nil];
}

+ (instancetype)configurationWithApplication:(FBSimulatorApplication *)application arguments:(NSArray *)arguments environment:(NSDictionary *)environment stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  FBApplicationLaunchConfiguration *configuration = [self new];
  configuration.application = application;
  configuration.arguments = arguments;
  configuration.environment = environment;
  configuration.stdOutPath = stdOutPath;
  configuration.stdErrPath = stdErrPath;
  return configuration;
}

- (NSString *)launchPath
{
  return self.application.binary.path;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBApplicationLaunchConfiguration *configuration = [super copyWithZone:zone];
  configuration.application = self.application;
  return configuration;
}

- (NSUInteger)hash
{
  return [super hash] | self.application.hash;
}

- (BOOL)isEqual:(FBApplicationLaunchConfiguration *)object
{
  return [super isEqual:object] && [self.application isEqual:object.application];
}

- (NSString *)longDescription
{
  return [NSString stringWithFormat:
    @"App Launch | Application %@ | Arguments %@ | Environment %@ | StdOut %@ | StdErr %@",
    self.application,
    self.arguments,
    self.environment,
    self.stdOutPath,
    self.stdErrPath
  ];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:@"App Launch %@", self.application.name];
}

@end

@implementation FBAgentLaunchConfiguration

+ (instancetype)configurationWithBinary:(FBSimulatorBinary *)agentBinary arguments:(NSArray *)arguments environment:(NSDictionary *)environment
{
  return [self configurationWithBinary:agentBinary arguments:arguments environment:environment stdOutPath:nil stdErrPath:nil];
}

+ (instancetype)configurationWithBinary:(FBSimulatorBinary *)agentBinary arguments:(NSArray *)arguments environment:(NSDictionary *)environment stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  FBAgentLaunchConfiguration *configuration = [self new];
  configuration.agentBinary = agentBinary;
  configuration.arguments = arguments;
  configuration.environment = environment;
  configuration.stdOutPath = stdOutPath;
  configuration.stdErrPath = stdErrPath;
  return configuration;
}

- (NSString *)launchPath
{
  return self.agentBinary.path;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [self.class
          configurationWithBinary:self.agentBinary
          arguments:self.arguments
          environment:self.environment];
}

- (BOOL)isEqual:(FBAgentLaunchConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return [self.agentBinary isEqual:object.agentBinary] &&
  [self.arguments isEqual:object.arguments] &&
  [self.environment isEqual:object.environment];
}

- (NSString *)longDescription
{
  return [NSString stringWithFormat:
    @"Agent Launch | Binary %@ | Arguments %@ | Environment %@ | StdOut %@ | StdErr %@",
    self.agentBinary,
    self.arguments,
    self.environment,
    self.stdOutPath,
    self.stdErrPath
  ];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:@"Agent Launch %@", self.agentBinary.name];
}

@end
