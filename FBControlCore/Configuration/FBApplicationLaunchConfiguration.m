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

FBiOSTargetActionType const FBiOSTargetActionTypeApplicationLaunch = @"applaunch";

static NSString *const KeyBundleID = @"bundle_id";
static NSString *const KeyBundleName = @"bundle_name";
static NSString *const KeyWaitForDebugger = @"wait_for_debugger";

@implementation FBApplicationLaunchConfiguration

+ (instancetype)configurationWithBundleID:(NSString *)bundleID bundleName:(NSString *)bundleName arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger output:(FBProcessOutputConfiguration *)output
{
  if (!bundleID || !arguments || !environment) {
    return nil;
  }

  return [[self alloc] initWithBundleID:bundleID bundleName:bundleName arguments:arguments environment:environment waitForDebugger:waitForDebugger output:output];
}

+ (instancetype)configurationWithApplication:(FBApplicationDescriptor *)application arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger output:(FBProcessOutputConfiguration *)output
{
  if (!application) {
    return nil;
  }

  return [self configurationWithBundleID:application.bundleID bundleName:application.name arguments:arguments environment:environment waitForDebugger:waitForDebugger output:output];
}

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  NSString *bundleID = json[KeyBundleID];
  if (![bundleID isKindOfClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a bundle_id", bundleID] fail:error];
  }
  NSString *bundleName = json[KeyBundleName];
  if (bundleName && ![bundleName isKindOfClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a bundle_name", bundleName] fail:error];
  }
  NSNumber *waitForDebugger = json[KeyWaitForDebugger] ?: @NO;
  if (![waitForDebugger isKindOfClass:NSNumber.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a boolean signalizing whether to wait for debugger", waitForDebugger] fail:error];
  }
  NSArray<NSString *> *arguments = nil;
  NSDictionary<NSString *, NSString *> *environment = nil;
  FBProcessOutputConfiguration *output = nil;
  if (![FBProcessLaunchConfiguration fromJSON:json extractArguments:&arguments environment:&environment output:&output error:error]) {
    return nil;
  }
  return [self configurationWithBundleID:bundleID bundleName:bundleName arguments:arguments environment:environment waitForDebugger:waitForDebugger.boolValue output:output];
}

- (instancetype)initWithBundleID:(NSString *)bundleID bundleName:(NSString *)bundleName arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger output:(FBProcessOutputConfiguration *)output
{
  self = [super initWithArguments:arguments environment:environment output:output];
  if (!self) {
    return nil;
  }

  _bundleID = bundleID;
  _bundleName = bundleName;
  _waitForDebugger = waitForDebugger;

  return self;
}

- (instancetype)withOutput:(FBProcessOutputConfiguration *)output
{
    return [[FBApplicationLaunchConfiguration alloc]
      initWithBundleID:self.bundleID
      bundleName:self.bundleName
      arguments:self.arguments
      environment:self.environment
      waitForDebugger:self.waitForDebugger
      output:output];
}

#pragma mark Abstract Methods

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"%@ | Arguments %@ | Environment %@ | WaitForDebugger %@ | Output %@",
    self.shortDescription,
    [FBCollectionInformation oneLineDescriptionFromArray:self.arguments],
    [FBCollectionInformation oneLineDescriptionFromDictionary:self.environment],
    self.waitForDebugger ? @"YES" : @"NO",
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
    waitForDebugger:self.waitForDebugger
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
  _waitForDebugger = [coder decodeBoolForKey:NSStringFromSelector(@selector(waitForDebugger))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [super encodeWithCoder:coder];

  [coder encodeObject:self.bundleID forKey:NSStringFromSelector(@selector(bundleID))];
  [coder encodeObject:self.bundleName forKey:NSStringFromSelector(@selector(bundleName))];
  [coder encodeBool:self.waitForDebugger forKey:NSStringFromSelector(@selector(waitForDebugger))];
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return [super hash] ^ self.bundleID.hash ^ self.bundleName.hash + (self.waitForDebugger ? 1231 : 1237);
}

- (BOOL)isEqual:(FBApplicationLaunchConfiguration *)object
{
  return [super isEqual:object] &&
         [self.bundleID isEqualToString:object.bundleID] &&
         (self.bundleName == object.bundleName || [self.bundleName isEqual:object.bundleName]) &&
          self.waitForDebugger == object.waitForDebugger;

}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  NSMutableDictionary *representation = [[super jsonSerializableRepresentation] mutableCopy];
  representation[KeyBundleID] = self.bundleID;
  representation[KeyBundleName] = self.bundleName;
  representation[KeyWaitForDebugger] = @(self.waitForDebugger);
  return [representation mutableCopy];
}

#pragma mark FBiOSTargetAction

+ (FBiOSTargetActionType)actionType
{
  return FBiOSTargetActionTypeApplicationLaunch;
}

- (BOOL)runWithTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSTargetActionDelegate>)delegate error:(NSError **)error
{
  return [target launchApplication:self error:error];
}

@end
