/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBApplicationInstallConfiguration.h"

#import "FBApplicationBundle+Install.h"
#import "FBApplicationBundle.h"
#import "FBCodesignProvider.h"
#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "NSRunLoop+FBControlCore.h"
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

- (FBiOSTargetFutureType)actionType
{
  return FBiOSTargetFutureTypeInstall;
}

- (FBFuture<FBiOSTargetFutureType> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBFileConsumer>)consumer reporter:(id<FBEventReporter>)reporter awaitableDelegate:(id<FBiOSTargetFutureAwaitableDelegate>)awaitableDelegate
{
  return [[[[FBApplicationBundle
    onQueue:target.asyncQueue findOrExtractApplicationAtPath:self.applicationPath]
    onQueue:target.workQueue fmap:^FBFuture *(FBExtractedApplication *extractedApplication) {
      if (self.codesign) {
        return [[FBCodesignProvider.codeSignCommandWithAdHocIdentity
          recursivelySignBundleAtPath:extractedApplication.bundle.path]
          mapReplace:extractedApplication];
      }
      return [[target
        installApplicationWithPath:extractedApplication.bundle.path]
        mapReplace:extractedApplication];
    }]
    onQueue:target.workQueue notifyOfCompletion:^(FBFuture<FBExtractedApplication *> *future) {
      if (future.result) {
        [NSFileManager.defaultManager removeItemAtURL:future.result.extractedPath error:nil];
      }
    }]
    mapReplace:self.actionType];
}

@end
