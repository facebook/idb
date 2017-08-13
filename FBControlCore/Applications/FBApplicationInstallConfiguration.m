/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBApplicationInstallConfiguration.h"

#import "FBiOSTarget.h"
#import "FBControlCoreError.h"
#import "FBCollectionInformation.h"
#import "FBApplicationBundle.h"
#import "FBCodesignProvider.h"

FBiOSTargetActionType const FBiOSTargetActionTypeInstall = @"install";

@implementation FBApplicationInstallConfiguration

#pragma mark Initializers.

+ (instancetype)applicationInstallWithPath:(NSString *)applicationPath codesign:(BOOL)codesign
{
  return [[self alloc] initWithPath:applicationPath codesign:codesign];
}

- (instancetype)initWithPath:(NSString *)applicationPath codesign:(BOOL)codesign
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _applicationPath = applicationPath;
  _codesign = codesign;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.applicationPath.hash ^ ((NSUInteger) self.codesign);
}

- (BOOL)isEqual:(FBApplicationInstallConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return [self.applicationPath isEqualToString:object.applicationPath]
      && self.codesign == object.codesign;
}

#pragma mark JSON

static NSString *const KeyApplicationPath = @"application_path";
static NSString *const KeyCodesign = @"codesign";

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Dictionary<String, Any>", json]
      fail:error];
  }
  NSString *applicationPath = json[KeyApplicationPath];
  if (![applicationPath isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a String for %@", applicationPath, KeyApplicationPath]
      fail:error];
  }
  NSNumber *codesign = json[KeyCodesign];
  if (![codesign isKindOfClass:NSNumber.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Number for %@", codesign, KeyCodesign]
      fail:error];
  }
  return [self applicationInstallWithPath:applicationPath codesign:codesign.boolValue];
}

- (id)jsonSerializableRepresentation
{
  return @{
    KeyApplicationPath: self.applicationPath,
    KeyCodesign: @(self.codesign),
  };
}

#pragma mark FBiOSTargetAction

+ (FBiOSTargetActionType)actionType
{
  return FBiOSTargetActionTypeInstall;
}

- (BOOL)runWithTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSTargetActionDelegate>)delegate error:(NSError **)error
{
  NSURL *extractPath = nil;
  NSString *applicationPath = [FBApplicationBundle findOrExtractApplicationAtPath:self.applicationPath extractPathOut:&extractPath error:error];
  if (![FBApplicationBundle findOrExtractApplicationAtPath:applicationPath extractPathOut:&extractPath error:error]) {
    return NO;
  }
  if (![FBCodesignProvider.codeSignCommandWithAdHocIdentity recursivelySignBundleAtPath:applicationPath error:error]) {
    return NO;
  }
  if (![target installApplicationWithPath:applicationPath error:error]) {
    return NO;
  }
  if (extractPath) {
    [NSFileManager.defaultManager removeItemAtURL:extractPath error:nil];
  }
  return YES;
}

@end
