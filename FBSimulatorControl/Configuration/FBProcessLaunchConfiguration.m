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
#import "FBSimulatorError.h"

@implementation FBProcessLaunchConfiguration

#pragma mark Initializers

- (instancetype)initWithArguments:(NSArray *)arguments environment:(NSDictionary *)environment stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
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

- (NSString *)launchPath
{
  NSAssert(NO, @"%@ is abstract", NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark FBDebugDescribeable

- (NSString *)shortDescription
{
  NSAssert(NO, @"%@ is abstract", NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)debugDescription
{
  NSAssert(NO, @"%@ is abstract", NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)description
{
  return [self debugDescription];
}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  return @{
    @"arguments" : self.arguments,
    @"environment" : self.environment,
    @"stdout_path" : self.stdOutPath ?: NSNull.null,
    @"stderr_path" : self.stdErrPath ?: NSNull.null,
  };
}

@end

@implementation FBApplicationLaunchConfiguration

+ (instancetype)configurationWithApplication:(FBSimulatorApplication *)application arguments:(NSArray *)arguments environment:(NSDictionary *)environment
{
  return [self configurationWithApplication:application arguments:arguments environment:environment stdOutPath:nil stdErrPath:nil];
}

+ (instancetype)configurationWithApplication:(FBSimulatorApplication *)application arguments:(NSArray *)arguments environment:(NSDictionary *)environment stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  return [self configurationWithBundleID:application.bundleID bundleName:application.name arguments:arguments environment:environment stdOutPath:stdOutPath stdErrPath:stdErrPath];
}

+ (instancetype)configurationWithBundleID:(NSString *)bundleID bundleName:(NSString *)bundleName arguments:(NSArray *)arguments environment:(NSDictionary *)environment
{
  return [self configurationWithBundleID:bundleID bundleName:bundleName arguments:arguments environment:environment stdOutPath:nil stdErrPath:nil];
}

+ (instancetype)configurationWithBundleID:(NSString *)bundleID bundleName:(NSString *)bundleName arguments:(NSArray *)arguments environment:(NSDictionary *)environment stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  if (!bundleID || !arguments || !environment) {
    return nil;
  }

  return [[self alloc] initWithBundleID:bundleID bundleName:bundleName arguments:arguments environment:environment stdOutPath:stdOutPath stdErrPath:stdErrPath];
}

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  NSString *bundleID = json[@"bundle_id"];
  if (![bundleID isKindOfClass:NSString.class]) {
    return [[FBSimulatorError describeFormat:@"%@ is not a bundle_id", bundleID] fail:error];
  }
  NSString *bundleName = json[@"bundle_name"];
  if (![bundleName isKindOfClass:NSString.class]) {
    return [[FBSimulatorError describeFormat:@"%@ is not a bundle_name", bundleName] fail:error];
  }
  NSArray *arguments = json[@"arguments"];
  if (![FBCollectionInformation isArrayHeterogeneous:arguments withClass:NSString.class]) {
    return [[FBSimulatorError describeFormat:@"%@ is not an array of strings for arguments", arguments] fail:error];
  }
  NSDictionary *environment = json[@"environment"];
  if (![FBCollectionInformation isDictionaryHeterogeneous:environment keyClass:NSString.class valueClass:NSString.class]) {
    return [[FBSimulatorError describeFormat:@"%@ is not an dictionary of <string, strings> for environment", arguments] fail:error];
  }
  return [self configurationWithBundleID:bundleID bundleName:bundleName arguments:arguments environment:environment];
}

- (instancetype)initWithBundleID:(NSString *)bundleID bundleName:(NSString *)bundleName arguments:(NSArray *)arguments environment:(NSDictionary *)environment stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  self = [super initWithArguments:arguments environment:environment stdOutPath:stdOutPath stdErrPath:stdErrPath];
  if (!self) {
    return nil;
  }

  _bundleID = bundleID;
  _bundleName = bundleName;

  return self;
}

#pragma mark Abstract Methods

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"%@ | Arguments %@ | Environment %@ | StdOut %@ | StdErr %@",
    self.shortDescription,
    self.arguments,
    self.environment,
    self.stdOutPath,
    self.stdErrPath
  ];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:@"App Launch %@ (%@)", self.bundleID, self.bundleName];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc]
    initWithBundleID:self.bundleID
    bundleName:self.bundleName
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

  _bundleID = [coder decodeObjectForKey:NSStringFromSelector(@selector(bundleID))];
  _bundleName = [coder decodeObjectForKey:NSStringFromSelector(@selector(bundleName))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [super encodeWithCoder:coder];

  [coder encodeObject:self.bundleID forKey:NSStringFromSelector(@selector(bundleID))];
  [coder encodeObject:self.bundleName forKey:NSStringFromSelector(@selector(bundleName))];
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return [super hash] ^ self.bundleID.hash ^ self.bundleName.hash;
}

- (BOOL)isEqual:(FBApplicationLaunchConfiguration *)object
{
  return [super isEqual:object] &&
         [self.bundleID isEqualToString:object.bundleID] &&
         (self.bundleName == object.bundleName || [self.bundleName isEqual:object.bundleName]);
}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  NSMutableDictionary *representation = [[super jsonSerializableRepresentation] mutableCopy];
  representation[@"bundle_id"] = self.bundleID;
  representation[@"bundle_name"] = self.bundleName;
  return [representation mutableCopy];
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

- (NSString *)debugDescription
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

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  NSMutableDictionary *representation = [[super jsonSerializableRepresentation] mutableCopy];
  representation[@"binary"] = [self.agentBinary jsonSerializableRepresentation];
  return [representation mutableCopy];
}

@end
