/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FakeNotificationSettingsGateway : NSObject
- (nullable id)sectionInfoForSectionID:(NSString *)sectionID;
- (void)setSectionInfo:(id)sectionInfo forSectionID:(NSString *)sectionID;
- (NSArray<NSString *> *)allSectionIDs;
@end

BOOL FBNotificationAllowsNotifications(id _Nullable sectionInfo);
NSInteger FBNotificationAuthorizationStatus(id _Nullable sectionInfo);

int handleNotificationSettingsActionWithGateway(NSString *action, NSString *_Nullable bundleID, id gateway);
Class _Nullable FBHealthAuthorizationStoreClass(void);
BOOL FBHealthRuntimeDeclaresSelector(NSString *selectorName);
NSException *_Nullable FBHealthApproveException(NSArray<NSString *> *types);

NS_ASSUME_NONNULL_END
