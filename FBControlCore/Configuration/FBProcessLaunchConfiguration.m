/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessLaunchConfiguration.h"
#import "FBProcessOutputConfiguration.h"

#import <FBControlCore/FBControlCore.h>

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

+ (BOOL)fromJSON:(id)json extractArguments:(NSArray<NSString *> **)argumentsOut environment:(NSDictionary<NSString *, NSString *> **)environmentOut output:(FBProcessOutputConfiguration **)outputOut error:(NSError **)error
{
  NSArray<NSString *> *arguments = json[KeyArguments] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:arguments withClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not an array of strings for %@", arguments, KeyArguments]
      failBool:error];
  }
  NSDictionary<NSString *, NSString *> *environment = json[KeyEnvironment] ?: @{};
  if (![FBCollectionInformation isDictionaryHeterogeneous:environment keyClass:NSString.class valueClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not an dictionary of <string, strings> for %@", arguments, KeyEnvironment]
      failBool:error];
  }
  FBProcessOutputConfiguration *output = [[FBProcessOutputConfiguration alloc] init];
  NSDictionary *outputDictionary = json[KeyOutput];
  if (outputDictionary) {
    output = [FBProcessOutputConfiguration inflateFromJSON:outputDictionary error:error];
    if (!output) {
      return NO;
    }
  }
  if (argumentsOut) {
    *argumentsOut = arguments;
  }
  if (environmentOut) {
    *environmentOut = environment;
  }
  if (outputOut) {
    *outputOut = output;
  }
  return YES;
}

@end
