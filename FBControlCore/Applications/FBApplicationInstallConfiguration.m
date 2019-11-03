/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBApplicationInstallConfiguration.h"

#import "FBBundleDescriptor+Application.h"
#import "FBBundleDescriptor.h"
#import "FBCodesignProvider.h"
#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBFuture+Sync.h"
#import "FBiOSTarget.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeInstall = @"install";

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

#pragma mark FBiOSTargetFuture

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeInstall;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  return [[[FBBundleDescriptor
    onQueue:target.asyncQueue findOrExtractApplicationAtPath:self.applicationPath logger:target.logger]
    onQueue:target.workQueue pop:^(FBBundleDescriptor *applicationBundle) {
      if (self.codesign) {
        return [FBCodesignProvider.codeSignCommandWithAdHocIdentity recursivelySignBundleAtPath:applicationBundle.path];
      }
      return [target installApplicationWithPath:applicationBundle.path];
    }]
    mapReplace:FBiOSTargetContinuationDone(self.class.futureType)];
}

@end
