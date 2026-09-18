/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBNotificationSectionValues : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly) BOOL allowsNotifications;
@property (nonatomic, readonly) NSUInteger authorizationStatus;
@property (nullable, nonatomic, readonly) NSNumber *showsInNotificationCenter;
@property (nullable, nonatomic, readonly) NSNumber *showsInLockScreen;
@end

/** A retained notification section, including the absence of a registered section. */
@interface FBNotificationSection : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly, getter = isFound) BOOL found;
- (nullable FBNotificationSectionValues *)readValuesWithError:(NSError **)error;
- (BOOL)setAllowsNotifications:(BOOL)allowed error:(NSError **)error;
- (BOOL)setAuthorizationStatus:(NSUInteger)status error:(NSError **)error;
- (BOOL)setAlertType:(NSUInteger)type error:(NSError **)error;
- (BOOL)setLockScreenSetting:(NSUInteger)setting error:(NSError **)error;
- (BOOL)setNotificationCenterSetting:(NSUInteger)setting error:(NSError **)error;
/** Writes each supported visibility flag and returns the names of absent flags. */
- (nullable NSArray<NSString *> *)setEffectiveVisibility:(BOOL)visible error:(NSError **)error;
@end

@interface FBNotificationSettingsClient : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
+ (nullable instancetype)liveClient;
- (instancetype)initWithGateway:(id)gateway;
- (nullable NSArray<NSString *> *)allSectionIDsWithError:(NSError **)error;
- (nullable FBNotificationSection *)sectionForIdentifier:(NSString *)identifier error:(NSError **)error;
- (nullable FBNotificationSection *)createSectionForIdentifier:(NSString *)identifier error:(NSError **)error;
- (BOOL)writeSection:(FBNotificationSection *)section forIdentifier:(NSString *)identifier error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
