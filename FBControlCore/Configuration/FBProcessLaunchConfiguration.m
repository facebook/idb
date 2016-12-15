/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessLaunchConfiguration.h"
#import "FBProcessOutputConfiguration.h"

#import <FBControlCore/FBControlCore.h>

static NSString *const OptionConnectStdout = @"connect_stdout";
static NSString *const OptionConnectStderr = @"connect_stderr";
static NSString *const KeyBundleID = @"bundle_id";
static NSString *const KeyBundleName = @"bundle_name";
static NSString *const KeyArguments = @"arguments";
static NSString *const KeyEnvironment = @"environment";
static NSString *const KeyOutput = @"output";

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

- (instancetype)withEnvironment:(NSDictionary<NSString *, NSString *> *)environment
{
  NSParameterAssert([FBCollectionInformation isDictionaryHeterogeneous:environment keyClass:NSString.class valueClass:NSString.class]);
  FBProcessLaunchConfiguration *configuration = [self copy];
  configuration->_environment = environment;
  return configuration;
}

- (instancetype)withArguments:(NSArray<NSString *> *)arguments
{
  NSParameterAssert([FBCollectionInformation isArrayHeterogeneous:arguments withClass:NSString.class]);
  FBProcessLaunchConfiguration *configuration = [self copy];
  configuration->_arguments = arguments;
  return configuration;
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
  _output = [coder decodeObjectForKey:NSStringFromSelector(@selector(output))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.arguments forKey:NSStringFromSelector(@selector(arguments))];
  [coder encodeObject:self.environment forKey:NSStringFromSelector(@selector(environment))];
  [coder encodeObject:self.output forKey:NSStringFromSelector(@selector(output))];
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
    KeyArguments : self.arguments,
    KeyEnvironment : self.environment,
    KeyOutput : self.output.jsonSerializableRepresentation,
  };
}

@end

@implementation FBApplicationLaunchConfiguration

+ (instancetype)configurationWithBundleID:(NSString *)bundleID bundleName:(NSString *)bundleName arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment output:(FBProcessOutputConfiguration *)output
{
  if (!bundleID || !arguments || !environment) {
    return nil;
  }

  return [[self alloc] initWithBundleID:bundleID bundleName:bundleName arguments:arguments environment:environment output:output];
}

+ (instancetype)configurationWithApplication:(FBApplicationDescriptor *)application arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment output:(FBProcessOutputConfiguration *)output
{
  if (!application) {
    return nil;
  }

  return [self configurationWithBundleID:application.bundleID bundleName:application.name arguments:arguments environment:environment output:output];
}

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  NSString *bundleID = json[KeyBundleID];
  if (![bundleID isKindOfClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a bundle_id", bundleID] fail:error];
  }
  NSString *bundleName = json[KeyBundleName];
  if (![bundleName isKindOfClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a bundle_name", bundleName] fail:error];
  }
  NSArray *arguments = json[KeyArguments];
  if (![FBCollectionInformation isArrayHeterogeneous:arguments withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not an array of strings for arguments", arguments] fail:error];
  }
  NSDictionary *environment = json[KeyEnvironment];
  if (![FBCollectionInformation isDictionaryHeterogeneous:environment keyClass:NSString.class valueClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not an dictionary of <string, strings> for environment", arguments] fail:error];
  }
  FBProcessOutputConfiguration *output = [FBProcessOutputConfiguration inflateFromJSON:json[KeyOutput] error:error];
  if (!output) {
    return nil;
  }
  return [self configurationWithBundleID:bundleID bundleName:bundleName arguments:arguments environment:environment output:output];
}

- (instancetype)initWithBundleID:(NSString *)bundleID bundleName:(NSString *)bundleName arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment output:(FBProcessOutputConfiguration *)output
{
  self = [super initWithArguments:arguments environment:environment output:output];
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
    @"%@ | Arguments %@ | Environment %@ | Output %@",
    self.shortDescription,
    self.arguments,
    self.environment,
    self.output
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
    output:self.output];
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
  representation[KeyBundleID] = self.bundleID;
  representation[KeyBundleName] = self.bundleName;
  return [representation mutableCopy];
}

@end

@implementation FBAgentLaunchConfiguration

+ (instancetype)configurationWithBinary:(FBBinaryDescriptor *)agentBinary arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment
{
  return [self configurationWithBinary:agentBinary arguments:arguments environment:environment output:FBProcessOutputConfiguration.defaultOutputToFile];
}

+ (instancetype)configurationWithBinary:(FBBinaryDescriptor *)agentBinary arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment output:(FBProcessOutputConfiguration *)output
{
  if (!agentBinary || !arguments || !environment) {
    return nil;
  }
  return [[self alloc] initWithBinary:agentBinary arguments:arguments environment:environment output:output];
}

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  NSError *innerError = nil;
  NSDictionary *binaryJSON = json[@"binary"];
  FBBinaryDescriptor *binary = [FBBinaryDescriptor inflateFromJSON:binaryJSON error:&innerError];
  if (!binary) {
    return [[[FBControlCoreError
      describeFormat:@"Could not build binary from json %@", binaryJSON]
      causedBy:innerError]
      fail:error];
  }
  NSArray *arguments = json[KeyArguments];
  if (![FBCollectionInformation isArrayHeterogeneous:arguments withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not an array of strings for arguments", arguments] fail:error];
  }
  NSDictionary *environment = json[KeyEnvironment];
  if (![FBCollectionInformation isDictionaryHeterogeneous:environment keyClass:NSString.class valueClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not an dictionary of <string, strings> for environment", arguments] fail:error];
  }
  FBProcessOutputConfiguration *output = [FBProcessOutputConfiguration inflateFromJSON:json[KeyOutput] error:error];
  if (!output) {
    return nil;
  }
  return [self configurationWithBinary:binary arguments:arguments environment:environment output:output];
}

- (instancetype)initWithBinary:(FBBinaryDescriptor *)agentBinary arguments:(NSArray *)arguments environment:(NSDictionary *)environment output:(FBProcessOutputConfiguration *)output
{
  self = [super initWithArguments:arguments environment:environment output:output];
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
    @"Agent Launch | Binary %@ | Arguments %@ | Environment %@ | Output %@",
    self.agentBinary,
    self.arguments,
    self.environment,
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
  return [[self.class alloc]
    initWithBinary:self.agentBinary
    arguments:self.arguments
    environment:self.environment
    output:self.output];
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
