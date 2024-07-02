/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBApplicationLaunchConfiguration.h"

@implementation FBApplicationLaunchConfiguration

- (instancetype)initWithBundleID:(NSString *)bundleID bundleName:(nullable NSString *)bundleName arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger io:(FBProcessIO *)io launchMode:(FBApplicationLaunchMode)launchMode
{
  self = [super initWithArguments:arguments environment:environment io:io];
  if (!self) {
    return nil;
  }

  _bundleID = bundleID;
  _bundleName = bundleName;
  _waitForDebugger = waitForDebugger;
  _launchMode = launchMode;

  return self;
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
    self.waitForDebugger == self.waitForDebugger &&
    self.launchMode == object.launchMode;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"App Launch %@ (%@)", self.bundleID, self.bundleName];
}

@end
