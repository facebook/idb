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

static NSString *const OptionConnectStdout = @"connect_stdout";
static NSString *const OptionConnectStderr = @"connect_stderr";

@implementation FBProcessLaunchConfiguration

#pragma mark Initializers

- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment options:(FBProcessLaunchOptions)options
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _arguments = arguments;
  _environment = environment;
  _options = options;

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
  _options = [[coder decodeObjectForKey:NSStringFromSelector(@selector(options))] unsignedIntegerValue];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.arguments forKey:NSStringFromSelector(@selector(arguments))];
  [coder encodeObject:self.environment forKey:NSStringFromSelector(@selector(environment))];
  [coder encodeObject:@(self.options) forKey:NSStringFromSelector(@selector(options))];
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.arguments.hash ^ self.environment.hash & self.options;
}

- (BOOL)isEqual:(FBProcessLaunchConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return [self.arguments isEqual:object.arguments] &&
         [self.environment isEqual:object.environment] &&
         self.options == object.options;
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
    @"options" : [FBProcessLaunchConfiguration optionNamesFromOptions:self.options],
  };
}

+ (NSArray<NSString *> *)optionNamesFromOptions:(FBProcessLaunchOptions)options
{
  NSMutableArray<NSString *> *names = [NSMutableArray array];
  if ((options & FBProcessLaunchOptionsWriteStdout) == FBProcessLaunchOptionsWriteStdout) {
    [names addObject:OptionConnectStdout];
  }
  if ((options & FBProcessLaunchOptionsWriteStderr) == FBProcessLaunchOptionsWriteStderr) {
    [names addObject:OptionConnectStderr];
  }
  return [names copy];
}

+ (FBProcessLaunchOptions)optionsFromOptionNames:(NSArray<NSString *> *)names
{
  FBProcessLaunchOptions options = 0;
  for (NSString *name in names) {
    if ([name isEqualToString:OptionConnectStdout]) {
      options = (options | FBProcessLaunchOptionsWriteStdout);
    }
    if ([name isEqualToString:OptionConnectStderr]) {
      options = (options | FBProcessLaunchOptionsWriteStderr);
    }
  }
  return options;
}

@end

@implementation FBApplicationLaunchConfiguration

+ (instancetype)configurationWithBundleID:(NSString *)bundleID bundleName:(NSString *)bundleName arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment options:(FBProcessLaunchOptions)options
{
  if (!bundleID || !arguments || !environment) {
    return nil;
  }

  return [[self alloc] initWithBundleID:bundleID bundleName:bundleName arguments:arguments environment:environment options:options];
}

+ (instancetype)configurationWithApplication:(FBSimulatorApplication *)application arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment options:(FBProcessLaunchOptions)options
{
  if (!application) {
    return nil;
  }

  return [self configurationWithBundleID:application.bundleID bundleName:application.name arguments:arguments environment:environment options:options];
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
  NSArray<NSString *> *optionNames = json[@"options"] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:optionNames withClass:NSString.class]) {
    return [[FBSimulatorError describeFormat:@"%@ is not an dictionary of <string, strings> for options", optionNames] fail:error];
  }
  FBProcessLaunchOptions options = [FBProcessLaunchConfiguration optionsFromOptionNames:optionNames];
  return [self configurationWithBundleID:bundleID bundleName:bundleName arguments:arguments environment:environment options:options];
}

- (instancetype)initWithBundleID:(NSString *)bundleID bundleName:(NSString *)bundleName arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment options:(FBProcessLaunchOptions)options
{
  self = [super initWithArguments:arguments environment:environment options:options];
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
    @"%@ | Arguments %@ | Environment %@ | Options %lu",
    self.shortDescription,
    self.arguments,
    self.environment,
    (unsigned long)self.options
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
    options:self.options];
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

+ (instancetype)configurationWithBinary:(FBSimulatorBinary *)agentBinary arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment
{
  return [self configurationWithBinary:agentBinary arguments:arguments environment:environment options:0];
}

+ (instancetype)configurationWithBinary:(FBSimulatorBinary *)agentBinary arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment options:(FBProcessLaunchOptions)options
{
  if (!agentBinary || !arguments || !environment) {
    return nil;
  }
  return [[self alloc] initWithBinary:agentBinary arguments:arguments environment:environment options:options];
}

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  NSError *innerError = nil;
  NSDictionary *binaryJSON = json[@"binary"];
  FBSimulatorBinary *binary = [FBSimulatorBinary inflateFromJSON:binaryJSON error:&innerError];
  if (!binary) {
    return [[[FBSimulatorError
      describeFormat:@"Could not build binary from json %@", binaryJSON]
      causedBy:innerError]
      fail:error];
  }
  NSArray *arguments = json[@"arguments"];
  if (![FBCollectionInformation isArrayHeterogeneous:arguments withClass:NSString.class]) {
    return [[FBSimulatorError describeFormat:@"%@ is not an array of strings for arguments", arguments] fail:error];
  }
  NSDictionary *environment = json[@"environment"];
  if (![FBCollectionInformation isDictionaryHeterogeneous:environment keyClass:NSString.class valueClass:NSString.class]) {
    return [[FBSimulatorError describeFormat:@"%@ is not an dictionary of <string, strings> for environment", arguments] fail:error];
  }
  NSArray<NSString *> *optionNames = json[@"options"] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:optionNames withClass:NSString.class]) {
    return [[FBSimulatorError describeFormat:@"%@ is not an dictionary of <string, strings> for options", optionNames] fail:error];
  }
  FBProcessLaunchOptions options = [FBProcessLaunchConfiguration optionsFromOptionNames:optionNames];
  return [self configurationWithBinary:binary arguments:arguments environment:environment options:options];
}

- (instancetype)initWithBinary:(FBSimulatorBinary *)agentBinary arguments:(NSArray *)arguments environment:(NSDictionary *)environment options:(FBProcessLaunchOptions)options
{
  self = [super initWithArguments:arguments environment:environment options:options];
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
    @"Agent Launch | Binary %@ | Arguments %@ | Environment %@ | Options %lu",
    self.agentBinary,
    self.arguments,
    self.environment,
    self.options
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
    options:self.options];
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
