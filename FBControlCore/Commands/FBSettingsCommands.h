/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An Enumeration Representing Approval of Services.
 */
typedef NSString *FBSettingsApprovalService NS_STRING_ENUM;

extern FBSettingsApprovalService const FBSettingsApprovalServiceContacts;
extern FBSettingsApprovalService const FBSettingsApprovalServicePhotos;
extern FBSettingsApprovalService const FBSettingsApprovalServiceCamera;
extern FBSettingsApprovalService const FBSettingsApprovalServiceLocation;
extern FBSettingsApprovalService const FBSettingsApprovalServiceMicrophone;
extern FBSettingsApprovalService const FBSettingsApprovalServiceUrl;
extern FBSettingsApprovalService const FBSettingsApprovalServiceNotification;

NS_ASSUME_NONNULL_END
