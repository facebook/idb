/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "PrivacyRuntime.h"

#import <dlfcn.h>

#import "TCCPrivate.h"

@implementation FBPrivacyOutcome
- (instancetype)initWithStatus:(FBPrivacyStatus)status reason:(NSString *)reason
{
  self = [super init];
  if (self) {
    _status = status;
    _failureReason = [reason copy];
  }
  return self;
}

+ (instancetype)completed { return [[self alloc] initWithStatus:FBPrivacyStatusCompleted reason:nil]; }

+ (instancetype)unavailable:(NSString *)reason { return [[self alloc] initWithStatus:FBPrivacyStatusUnavailable reason:reason]; }

+ (instancetype)failed:(NSString *)reason { return [[self alloc] initWithStatus:FBPrivacyStatusFailed reason:reason]; }

@end

@implementation FBPrivacyBinding
+ (FBPrivacyOutcome *)updateBundleID:(NSString *)bundleID services:(NSArray<NSString *> *)services approved:(BOOL)approved
{
  static void *framework;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    // Keep the image loaded: resolved entry points and exported CFStringRef values belong to it.
    framework = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_NOW);
  });
  if (!framework) {
    return [FBPrivacyOutcome unavailable:@"Could not load TCC.framework"];
  }
  return [self updateBundleID:bundleID
                     services:services
                     approved:approved
                     resolver:^void *(const char *name) {
                       return dlsym(framework, name);
                     }];
}

+ (FBPrivacyOutcome *)updateBundleID:(NSString *)bundleID services:(NSArray<NSString *> *)services approved:(BOOL)approved resolver:(FBPrivacySymbolResolver)resolver
{
  @try {
    FBTCCAccessSetForBundleIdWithOptions setAccess = NULL;
    FBTCCAccessResetForBundleIdWithOptions resetAccess = NULL;
    if (approved) {
      setAccess = resolver("TCCAccessSetForBundleIdWithOptions");
      if (!setAccess) {
        return [FBPrivacyOutcome unavailable:@"TCCAccessSetForBundleIdWithOptions unavailable"];
      }
    } else {
      resetAccess = resolver("TCCAccessResetForBundleIdWithOptions");
      if (!resetAccess) {
        return [FBPrivacyOutcome unavailable:@"TCCAccessResetForBundleIdWithOptions unavailable"];
      }
    }
    FBTCCNoKillSymbol noKill = resolver("kTCCSetNoKill");
    if (!noKill || !*noKill) {
      return [FBPrivacyOutcome unavailable:@"kTCCSetNoKill unavailable"];
    }
    // auth_value 2 is TCC's "allowed". Passing it explicitly is what makes Photos
    // report full authorization rather than a limited, user-chosen selection.
    NSDictionary *options = approved ? @{@"auth_value" : @2, (__bridge NSString *)*noKill : @YES}
    : @{(__bridge NSString *)*noKill : @YES};
    for (NSString *service in services) {
      Boolean accepted;
      if (approved) {
        accepted = setAccess((__bridge CFStringRef)service, (__bridge CFStringRef)bundleID, true, (__bridge CFDictionaryRef)options);
      } else {
        accepted = resetAccess((__bridge CFStringRef)service, (__bridge CFStringRef)bundleID, (__bridge CFDictionaryRef)options);
      }
      if (!accepted) {
        return [FBPrivacyOutcome failed:[NSString stringWithFormat:@"TCC %@ failed for %@ (%@); earlier services may already have changed", approved ? @"approval" : @"reset", bundleID, service]];
      }
    }
    return [FBPrivacyOutcome completed];
  } @catch (NSException *exception) {
    return [FBPrivacyOutcome failed:exception.reason ?: exception.name];
  }
}

@end
