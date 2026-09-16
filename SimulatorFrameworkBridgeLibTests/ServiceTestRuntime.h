/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

#import <SimulatorFrameworkBridgeLib/DeliveredNotificationsService.h>
#import <SimulatorFrameworkBridgeLib/DeliveredNotificationsService+Testing.h>

NS_ASSUME_NONNULL_BEGIN

@interface FakeNotificationSettingsGateway : NSObject
@property (nonatomic, readonly) NSMutableArray<NSString *> *writtenSectionIDs;
- (nullable id)sectionInfoForSectionID:(NSString *)sectionID;
- (void)setSectionInfo:(id)sectionInfo forSectionID:(NSString *)sectionID;
- (NSArray<NSString *> *)allSectionIDs;
@end

/**
 * A section info carrying `showsInNotificationCenter` but not `showsInLockScreen`, as a runtime
 * that gained the two flags separately hands one out. The flags are independent capabilities,
 * so this is the shape that tells a per-flag probe from an all-or-nothing one.
 */
@interface FBSectionInfoWithOnlyNotificationCenterFlag : NSObject
@property (nonatomic) BOOL allowsNotifications;
@property (nonatomic) NSUInteger authorizationStatus;
@property (nonatomic) NSUInteger alertType;
@property (nonatomic) NSUInteger lockScreenSetting;
@property (nonatomic) NSUInteger notificationCenterSetting;
@property (nonatomic) BOOL showsInNotificationCenter;
@end

/**
 * A section info as a runtime without the effective visibility flags hands one out: the
 * user-preference settings, and neither `showsInNotificationCenter` nor `showsInLockScreen`.
 */
@interface FBSectionInfoWithoutEffectiveFlags : NSObject
@property (nonatomic) BOOL allowsNotifications;
@property (nonatomic) NSUInteger authorizationStatus;
@property (nonatomic) NSUInteger alertType;
@property (nonatomic) NSUInteger lockScreenSetting;
@property (nonatomic) NSUInteger notificationCenterSetting;
@end

NSDictionary<NSString *, id> *FBNotificationSectionSnapshot(id sectionInfo);
void FBNotificationSetPresentation(id sectionInfo, NSUInteger alert, NSUInteger lockScreen, NSUInteger center);
NSDictionary<NSString *, id> *FBNotificationRunCommand(NSString *_Nullable action, NSString *_Nullable bundleID, id gateway);

BOOL FBNotificationAllowsNotifications(id _Nullable sectionInfo);
NSInteger FBNotificationAuthorizationStatus(id _Nullable sectionInfo);
BOOL FBNotificationShowsInNotificationCenter(id _Nullable sectionInfo);
BOOL FBNotificationShowsInLockScreen(id _Nullable sectionInfo);

/**
 * The services print their answers, so that is what there is to read them back from.
 *
 * The pipe is drained while the block runs rather than after it, so a block printing more than
 * a pipe buffer holds does not block forever inside `printf`. stdout is restored even if the
 * block raises: left on the pipe, stdout would stay there for the rest of the process with
 * nothing draining it, and one raising test would take the run down rather than fail on its own.
 */
NSString *FBStdoutWhileRunning(void (^block)(void));

/** The single JSON object in an answer that printed one record. */
NSDictionary<NSString *, id> *_Nullable FBParsedJSONLine(NSString *output);

int handleNotificationSettingsActionWithGateway(NSString *_Nullable action, NSString *_Nullable bundleID, id gateway);
Class _Nullable FBHealthAuthorizationStoreClass(void);
BOOL FBHealthRuntimeDeclaresSelector(NSString *selectorName);
NSException *_Nullable FBHealthApproveException(NSArray<NSString *> *types);

/** Exercises the runtime queue from Objective-C so no exception unwinds through Swift. */
NSDictionary<NSString *, NSNumber *> *FBAXRuntimeQueueProbe(BOOL raise);
/** Answers with whatever it was handed, so the reader runs without a notification daemon. */
@interface FBFakeDeliveredNotificationsCenter : NSObject <FBDeliveredNotificationsCenter>
/// `id` rather than `UNNotification *`: what the fake hands back stands in for one without
/// being one, which is the point of it.
@property (nullable, nonatomic, copy) NSArray<id> *notifications;
@property (nonatomic) BOOL wasAsked;
@end

/** Raises the way a runtime that has the selector but will not answer for the bundle does. */
@interface FBRaisingDeliveredNotificationsCenter : NSObject <FBDeliveredNotificationsCenter>
@end

/** Never answers, as a daemon that has stopped servicing the request does. */
@interface FBSilentDeliveredNotificationsCenter : NSObject <FBDeliveredNotificationsCenter>
@end

/** Answers from another queue, as the real daemon does. */
@interface FBAsynchronousDeliveredNotificationsCenter : NSObject <FBDeliveredNotificationsCenter>
@end

/**
 * Enough of a delivered notification for the mapping that turns one into JSON, which reads the
 * request, the request's content and the date. It stands in as its own request, and its content
 * is nil - a shape the mapping already answers for with empty strings.
 */
@interface FBFakeDeliveredNotification : NSObject
@property (nullable, nonatomic, copy) NSString *identifier;
@property (nullable, nonatomic, copy) NSDate *date;
@end

typedef NS_ENUM(NSInteger, FBAXRuntimeInitializationMode) {
  FBAXRuntimeInitializationModeSuccess,
  FBAXRuntimeInitializationModeFailureWithMessage,
  FBAXRuntimeInitializationModeFailureWithoutMessage,
  FBAXRuntimeInitializationModeExceptionWithReason,
  FBAXRuntimeInitializationModeExceptionWithoutReason,
};

/** Captures preparation exceptions in Objective-C before returning observations to Swift. */
NSDictionary<NSString *, id> *FBAXRuntimeInitializationProbe(FBAXRuntimeInitializationMode mode, BOOL prepare, NSDictionary<NSString *, id> *request);

NS_ASSUME_NONNULL_END
