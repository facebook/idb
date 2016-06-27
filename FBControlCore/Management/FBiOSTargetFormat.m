/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBiOSTargetFormat.h"

#import "FBiOSTarget.h"
#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreConfigurationVariants.h"
#import "FBProcessInfo.h"

NSString *const FBiOSTargetFormatUDID = @"udid";
NSString *const FBiOSTargetFormatName = @"name";
NSString *const FBiOSTargetFormatDeviceName = @"device-name";
NSString *const FBiOSTargetFormatOSVersion = @"os";
NSString *const FBiOSTargetFormatState = @"state";
NSString *const FBiOSTargetFormatProcessIdentifier = @"pid";

@implementation FBiOSTargetFormat

#pragma mark Initializers

+ (instancetype)formatWithFields:(NSArray<NSString *> *)fields
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
      FBiOSTargetFormatDeviceName,
      FBiOSTargetFormatOSVersion,
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
      FBiOSTargetFormatDeviceName,
      FBiOSTargetFormatOSVersion,
      FBiOSTargetFormatProcessIdentifier,
    ]];
  });
  return format;
}

- (instancetype)initWithFields:(NSArray<NSString *> *)fields
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

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  NSArray<NSString *> *fields = [coder decodeObjectForKey:NSStringFromSelector(@selector(fields))];
  return [self initWithFields:fields];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.fields forKey:NSStringFromSelector(@selector(fields))];
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

- (instancetype)appendFields:(NSArray<NSString *> *)fields
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
    if (!value) {
      continue;
    }
    [string appendString:([value isKindOfClass:NSString.class] ? value : [value stringValue])];
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

+ (nullable id)extract:(NSString *)field from:(id<FBiOSTarget>)target
{
  if ([field isEqualToString:FBiOSTargetFormatUDID]) {
    return target.udid;
  } else if ([field isEqualToString:FBiOSTargetFormatName]) {
    return target.name;
  } else if ([field isEqualToString:FBiOSTargetFormatDeviceName]) {
    return target.deviceConfiguration.deviceName;
  } else if ([field isEqualToString:FBiOSTargetFormatOSVersion]) {
    return target.osConfiguration.name;
  } else if ([field isEqualToString:FBiOSTargetFormatState]) {
    return FBSimulatorStateStringFromState(target.state);
  } else if ([field isEqualToString:FBiOSTargetFormatProcessIdentifier]) {
    return @(target.launchdProcess.processIdentifier);
  }
  return nil;
}

@end
