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

static NSString *const KeyBinary = @"binary";

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
  NSDictionary *binaryJSON = json[KeyBinary];
  FBBinaryDescriptor *binary = [FBBinaryDescriptor inflateFromJSON:binaryJSON error:&innerError];
  if (!binary) {
    return [[[FBControlCoreError
      describeFormat:@"Could not build %@ from json %@", KeyBinary, binaryJSON]
      causedBy:innerError]
      fail:error];
  }
  NSArray<NSString *> *arguments = nil;
  NSDictionary<NSString *, NSString *> *environment = nil;
  FBProcessOutputConfiguration *output = nil;
  if (![FBProcessLaunchConfiguration fromJSON:json extractArguments:&arguments environment:&environment output:&output error:error]) {
    return nil;
  }
  return [self configurationWithBinary:binary arguments:arguments environment:environment output:output];
}

- (instancetype)initWithBinary:(FBBinaryDescriptor *)agentBinary arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment output:(FBProcessOutputConfiguration *)output
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
