/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An Enumeration Representing Services.
 */
typedef NSString *FBTargetSettingsService NS_STRING_ENUM;

extern FBTargetSettingsService const FBTargetSettingsServiceContacts;
extern FBTargetSettingsService const FBTargetSettingsServicePhotos;
extern FBTargetSettingsService const FBTargetSettingsServiceCamera;
extern FBTargetSettingsService const FBTargetSettingsServiceLocation;
extern FBTargetSettingsService const FBTargetSettingsServiceMicrophone;
extern FBTargetSettingsService const FBTargetSettingsServiceUrl;
extern FBTargetSettingsService const FBTargetSettingsServiceNotification;

NS_ASSUME_NONNULL_END
