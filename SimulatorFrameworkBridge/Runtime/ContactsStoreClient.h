/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <TargetConditionals.h>

#import <Foundation/Foundation.h>

#if !TARGET_OS_TV
 #import <Contacts/Contacts.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBContactsStoreClient : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithStore:(CNContactStore *)store NS_DESIGNATED_INITIALIZER;
- (nullable NSArray<CNContact *> *)fetchContactsWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NOTHROW NS_SWIFT_NAME(fetchContacts(error:));
- (BOOL)executeSaveRequest:(CNSaveRequest *)request error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NOTHROW NS_SWIFT_NAME(execute(_:error:));
@end

NS_ASSUME_NONNULL_END
#endif
