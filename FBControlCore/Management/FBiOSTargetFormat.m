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

@implementation FBiOSTargetFormat

#pragma mark Initializers

+ (instancetype)formatWithFields:(NSArray<FBiOSTargetFormatKey> *)fields
{
  NSParameterAssert([FBCollectionInformation isArrayHeterogeneous:fields withClass:NSString.class]);
  return [[self alloc] initWithFields:fields];
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
  }
  return nil;
}

@end
