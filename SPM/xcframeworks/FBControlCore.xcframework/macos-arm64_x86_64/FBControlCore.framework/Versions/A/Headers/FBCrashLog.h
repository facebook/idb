/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@protocol FBControlCoreLogger;
@protocol FBCrashLogParser;

/**
 An emuration representing the kind of process that has crashed.
*/
typedef NS_OPTIONS(NSUInteger, FBCrashLogInfoProcessType) {
  FBCrashLogInfoProcessTypeSystem = 1 << 0, /** A process that is part of the operating system runtime */
  FBCrashLogInfoProcessTypeApplication = 1 << 1, /** A process that is an application **/
  FBCrashLogInfoProcessTypeCustom = 1 << 2, /** A process that not an application nor part of the operating system runtime **/
};
