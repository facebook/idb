/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Routes `<service> <action> [args...]` to the matching `handle*Action`. Returns 1 for an unknown service. */
int dispatchService(NSString *service, NSString *action, NSArray<NSString *> *arguments);

@protocol FBBridgeServiceHandling <NSObject>
#if !TARGET_OS_TV
- (int32_t)contacts:(NSString *)action;
- (int32_t)health:(NSString *)action bundleID:(nullable NSString *)bundleID typeIDs:(NSArray<NSString *> *)typeIDs;
#endif
- (int32_t)dns:(NSString *)action arguments:(NSArray<NSString *> *)arguments;
- (int32_t)dynamicStore:(NSString *)action arguments:(NSArray<NSString *> *)arguments;
- (int32_t)photos:(NSString *)action;
- (int32_t)notifications:(NSString *)action bundleID:(nullable NSString *)bundleID;
- (int32_t)proxy:(NSString *)action arguments:(NSArray<NSString *> *)arguments;
- (int32_t)accessibility:(NSString *)action arguments:(NSArray<NSString *> *)arguments;
- (int32_t)repl:(nullable NSString *)socketPath libraryPath:(NSString *)libraryPath;
@end

@interface FBBridgeCommand : NSObject
+ (int32_t)runWithArguments:(NSArray<NSString *> *)arguments services:(id<FBBridgeServiceHandling>)services NS_SWIFT_NAME(run(arguments:services:));
+ (int32_t)dispatchWithService:(NSString *)service action:(NSString *)action arguments:(NSArray<NSString *> *)arguments services:(id<FBBridgeServiceHandling>)services NS_SWIFT_NAME(dispatch(service:action:arguments:services:));
@end

int runBridgeCommand(NSArray<NSString *> *arguments);

NS_ASSUME_NONNULL_END
