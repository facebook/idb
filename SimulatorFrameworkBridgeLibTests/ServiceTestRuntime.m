/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ServiceTestRuntime.h"

#import <dlfcn.h>
#import <objc/runtime.h>

#import <SimulatorFrameworkBridgeLib/BulletinBoardPrivate.h>
#import <SimulatorFrameworkBridgeLib/HealthSettingsService.h>

@interface FakeNotificationSettingsGateway ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, BBSectionInfo *> *sections;
@end

@implementation FakeNotificationSettingsGateway
- (instancetype)init
{
  self = [super init];
  if (self) {
    _sections = [NSMutableDictionary dictionary];
  }
  return self;
}

- (id)sectionInfoForSectionID:(NSString *)sectionID
{
  return self.sections[sectionID];
}

- (void)setSectionInfo:(id)sectionInfo forSectionID:(NSString *)sectionID
{
  self.sections[sectionID] = sectionInfo;
}

- (NSArray<NSString *> *)allSectionIDs
{
  return self.sections.allKeys;
}

@end

Class FBHealthAuthorizationStoreClass(void)
{
  dlopen("/System/Library/Frameworks/HealthKit.framework/HealthKit", RTLD_NOW);
  return objc_lookUpClass("HKAuthorizationStore");
}

BOOL FBHealthRuntimeDeclaresSelector(NSString *selectorName)
{
  Class cls = FBHealthAuthorizationStoreClass();
  return cls != Nil && [cls instancesRespondToSelector:NSSelectorFromString(selectorName)];
}

NSException *FBHealthApproveException(NSArray<NSString *> *types)
{
  @try {
    handleHealthSettingsAction(@"approve", @"com.example.test", types);
    return nil;
  } @catch (NSException *exception) {
    return exception;
  }
}

BOOL FBNotificationAllowsNotifications(id sectionInfo)
{
  return [(BBSectionInfo *)sectionInfo allowsNotifications];
}

NSInteger FBNotificationAuthorizationStatus(id sectionInfo)
{
  return [(BBSectionInfo *)sectionInfo authorizationStatus];
}
