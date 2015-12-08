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

#pragma mark Initializers

- (instancetype)initWithArguments:(NSArray *)arguments environment:(NSDictionary *)environment stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  NSParameterAssert(arguments);
  NSParameterAssert(environment);

  self = [super init];
  if (!self) {
    return nil;
  }

  _arguments = arguments;
  _environment = environment;
  _stdOutPath = stdOutPath;
  _stdErrPath = stdErrPath;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  NSAssert(NO, @"%@ is abstract", NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _arguments = [coder decodeObjectForKey:NSStringFromSelector(@selector(arguments))];
  _environment = [coder decodeObjectForKey:NSStringFromSelector(@selector(environment))];
  _stdOutPath = [coder decodeObjectForKey:NSStringFromSelector(@selector(stdOutPath))];
  _stdErrPath = [coder decodeObjectForKey:NSStringFromSelector(@selector(stdErrPath))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.arguments forKey:NSStringFromSelector(@selector(arguments))];
  [coder encodeObject:self.environment forKey:NSStringFromSelector(@selector(environment))];
  [coder encodeObject:self.stdOutPath forKey:NSStringFromSelector(@selector(stdOutPath))];
  [coder encodeObject:self.stdErrPath forKey:NSStringFromSelector(@selector(stdErrPath))];
}

#pragma mark NSObject

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
  return [self longDescription];
}

@end

@implementation FBApplicationLaunchConfiguration

+ (instancetype)configurationWithApplication:(FBSimulatorApplication *)application arguments:(NSArray *)arguments environment:(NSDictionary *)environment
{
  return [self configurationWithApplication:application arguments:arguments environment:environment stdOutPath:nil stdErrPath:nil];
}

+ (instancetype)configurationWithApplication:(FBSimulatorApplication *)application arguments:(NSArray *)arguments environment:(NSDictionary *)environment stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  if (!application || !arguments || !environment) {
    return nil;
  }

  return [[self alloc] initWithApplication:application arguments:arguments environment:environment stdOutPath:stdOutPath stdErrPath:stdErrPath];
}

- (instancetype)initWithApplication:(FBSimulatorApplication *)application arguments:(NSArray *)arguments environment:(NSDictionary *)environment stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  NSParameterAssert(application);

  self = [super initWithArguments:arguments environment:environment stdOutPath:stdOutPath stdErrPath:stdErrPath];
  if (!self) {
    return nil;
  }

  _application = application;

  return self;
}

#pragma mark Abstract Methods

- (NSString *)launchPath
{
  return self.application.binary.path;
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

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc]
    initWithApplication:self.application
    arguments:self.arguments
    environment:self.environment
    stdOutPath:self.stdOutPath
    stdErrPath:self.stdErrPath];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (!self) {
    return nil;
  }

  _application = [coder decodeObjectForKey:NSStringFromSelector(@selector(application))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [super encodeWithCoder:coder];

  [coder encodeObject:self.application forKey:NSStringFromSelector(@selector(application))];
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return [super hash] | self.application.hash;
}

- (BOOL)isEqual:(FBApplicationLaunchConfiguration *)object
{
  return [super isEqual:object] && [self.application isEqual:object.application];
}

@end

@implementation FBAgentLaunchConfiguration

+ (instancetype)configurationWithBinary:(FBSimulatorBinary *)agentBinary arguments:(NSArray *)arguments environment:(NSDictionary *)environment
{
  return [self configurationWithBinary:agentBinary arguments:arguments environment:environment stdOutPath:nil stdErrPath:nil];
}

+ (instancetype)configurationWithBinary:(FBSimulatorBinary *)agentBinary arguments:(NSArray *)arguments environment:(NSDictionary *)environment stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  if (!agentBinary || !arguments || !environment) {
    return nil;
  }
  return [[self alloc] initWithBinary:agentBinary arguments:arguments environment:environment stdOutPath:stdOutPath stdErrPath:stdErrPath];
}

- (instancetype)initWithBinary:(FBSimulatorBinary *)agentBinary arguments:(NSArray *)arguments environment:(NSDictionary *)environment stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  self = [super initWithArguments:arguments environment:environment stdOutPath:stdOutPath stdErrPath:stdErrPath];
  if (!self) {
    return nil;
  }

  _agentBinary = agentBinary;

  return self;
}

#pragma mark Abstract Methods

- (NSString *)launchPath
{
  return self.agentBinary.path;
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

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc]
    initWithBinary:self.agentBinary
    arguments:self.arguments
    environment:self.environment
    stdOutPath:self.stdOutPath
    stdErrPath:self.stdErrPath];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (!self) {
    return nil;
  }

  _agentBinary = [coder decodeObjectForKey:NSStringFromSelector(@selector(agentBinary))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [super encodeWithCoder:coder];

  [coder encodeObject:self.agentBinary forKey:NSStringFromSelector(@selector(agentBinary))];
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return [super hash] | self.agentBinary.hash;
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

@end
