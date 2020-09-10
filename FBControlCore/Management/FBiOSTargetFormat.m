/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetFormat.h"

#import "FBiOSTarget.h"
#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBiOSTargetConfiguration.h"
#import "FBProcessInfo.h"

FBiOSTargetFormatKey const FBiOSTargetFormatUDID = @"udid";
FBiOSTargetFormatKey const FBiOSTargetFormatName = @"name";
FBiOSTargetFormatKey const FBiOSTargetFormatModel = @"model";
FBiOSTargetFormatKey const FBiOSTargetFormatOSVersion = @"os";
FBiOSTargetFormatKey const FBiOSTargetFormatState = @"state";
FBiOSTargetFormatKey const FBiOSTargetFormatArchitecture = @"arch";
FBiOSTargetFormatKey const FBiOSTargetFormatProcessIdentifier = @"pid";
FBiOSTargetFormatKey const FBiOSTargetFormatContainerApplicationProcessIdentifier = @"container-pid";

@implementation FBiOSTargetFormat

+ (NSDictionary<NSString *, FBiOSTargetFormatKey> *)formatMapping
{
  return @{
    @"a" : FBiOSTargetFormatArchitecture,
    @"m" : FBiOSTargetFormatModel,
    @"n" : FBiOSTargetFormatName,
    @"o" : FBiOSTargetFormatOSVersion,
    @"p" : FBiOSTargetFormatProcessIdentifier,
    @"s" : FBiOSTargetFormatState,
    @"u" : FBiOSTargetFormatUDID,
  };
}

#pragma mark Initializers

+ (instancetype)formatWithFields:(NSArray<FBiOSTargetFormatKey> *)fields
{
  NSParameterAssert([FBCollectionInformation isArrayHeterogeneous:fields withClass:NSString.class]);
  return [[self alloc] initWithFields:fields];
}

+ (nullable instancetype)formatWithString:(NSString *)string error:(NSError **)error
{
  NSArray<NSString *> *components = [string componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"%@"]];
  NSDictionary<NSString *, FBiOSTargetFormatKey> *mapping = [self formatMapping];
  NSMutableArray<FBiOSTargetFormatKey> *keys = [NSMutableArray array];
  for (NSString *component in components) {
    if (component.length == 0) {
      continue;
    }
    FBiOSTargetFormatKey key = mapping[component];
    if (!key) {
      return [[FBControlCoreError
        describeFormat:@"%@ is not a valid format in %@", component, [FBCollectionInformation oneLineDescriptionFromArray:mapping.allKeys]]
        fail:error];
    }
    [keys addObject:key];
  }
  return [self formatWithFields:[keys copy]];
}

+ (instancetype)defaultFormat
{
  static dispatch_once_t onceToken;
  static FBiOSTargetFormat *format;
  dispatch_once(&onceToken, ^{
    format = [FBiOSTargetFormat formatWithFields:@[
      FBiOSTargetFormatUDID,
      FBiOSTargetFormatName,
      FBiOSTargetFormatState,
      FBiOSTargetFormatModel,
      FBiOSTargetFormatOSVersion,
      FBiOSTargetFormatArchitecture,
    ]];
  });
  return format;
}

+ (instancetype)fullFormat
{
  static dispatch_once_t onceToken;
  static FBiOSTargetFormat *format;
  dispatch_once(&onceToken, ^{
    format = [FBiOSTargetFormat formatWithFields:@[
      FBiOSTargetFormatUDID,
      FBiOSTargetFormatName,
      FBiOSTargetFormatState,
      FBiOSTargetFormatModel,
      FBiOSTargetFormatOSVersion,
      FBiOSTargetFormatArchitecture,
      FBiOSTargetFormatProcessIdentifier,
      FBiOSTargetFormatContainerApplicationProcessIdentifier,
    ]];
  });
  return format;
}

- (instancetype)initWithFields:(NSArray<FBiOSTargetFormatKey> *)fields
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fields = fields;

  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBiOSTargetFormat *)object
{
  if (![object isKindOfClass:FBiOSTargetFormat.class]) {
    return NO;
  }
  return [self.fields isEqualToArray:object.fields];
}

- (NSUInteger)hash
{
  return self.fields.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Format %@", [FBCollectionInformation oneLineDescriptionFromArray:self.fields]];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark JSON

- (id)jsonSerializableRepresentation
{
  return self.fields;
}

+ (instancetype)inflateFromJSON:(NSArray<NSString *> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isArrayHeterogeneous:json withClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not an Array of Strings", json]
      fail:error];
  }
  return [self formatWithFields:json];
}

#pragma mark Public

- (instancetype)appendFields:(NSArray<FBiOSTargetFormatKey> *)fields
{
  if (fields.count == 0) {
    return self;
  }
  return [[self.class alloc] initWithFields:[self.fields arrayByAddingObjectsFromArray:fields]];
}

- (instancetype)appendField:(NSString *)field
{
  NSParameterAssert(field);
  return [self appendFields:@[field]];
}

- (NSString *)format:(id<FBiOSTarget>)target
{
  NSMutableString *string = [NSMutableString string];
  for (NSUInteger index = 0; index < self.fields.count; index++) {
    NSString *field = self.fields[index];
    id value = [FBiOSTargetFormat extract:field from:target];
    if (!value || value == [NSNull null]) {
      continue;
    }
    [string appendString:([value respondsToSelector:@selector(stringValue)] ? [value stringValue] : value)];
    if (index >= self.fields.count - 1) {
      continue;
    }
    [string appendString:@" | "];
  }
  return [string copy];
}

- (NSDictionary<NSString *, id> *)extractFrom:(id<FBiOSTarget>)target
{
  NSMutableDictionary<NSString *, id> *dictionary = [NSMutableDictionary dictionary];
  for (NSString *field in self.fields) {
    id value = [FBiOSTargetFormat extract:field from:target];
    if (!value) {
      continue;
    }
    dictionary[field] = value;
  }
  return [dictionary copy];
}

+ (nullable id)extract:(FBiOSTargetFormatKey)field from:(id<FBiOSTarget>)target
{
  if ([field isEqualToString:FBiOSTargetFormatUDID]) {
    return target.udid;
  } else if ([field isEqualToString:FBiOSTargetFormatName]) {
    return target.name;
  } else if ([field isEqualToString:FBiOSTargetFormatModel]) {
    return target.deviceType.model;
  } else if ([field isEqualToString:FBiOSTargetFormatOSVersion]) {
    return target.osVersion.name;
  } else if ([field isEqualToString:FBiOSTargetFormatState]) {
    return FBiOSTargetStateStringFromState(target.state);
  } else if ([field isEqualToString:FBiOSTargetFormatArchitecture]) {
    return target.architecture;
  } else if ([field isEqualToString:FBiOSTargetFormatProcessIdentifier]) {
    return @(target.launchdProcess.processIdentifier);
  } else if ([field isEqualToString:FBiOSTargetFormatContainerApplicationProcessIdentifier]) {
    return @(target.containerApplication.processIdentifier);
  }
  return nil;
}

@end
