/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceControlFrameworkLoader.h"

#import <FBControlCore/FBControlCore.h>

#import <DVTFoundation/DVTDeviceManager.h>
#import <DVTFoundation/DVTDeviceType.h>
#import <DVTFoundation/DVTLogAspect.h>
#import <DVTFoundation/DVTPlatform.h>

#import <IDEFoundation/IDEFoundationTestInitializer.h>

#import <objc/runtime.h>

#import "FBDeviceControlError.h"
#import "FBAMDevice.h"

static BOOL hasLoadedEssentialFrameworks = NO;
static BOOL hasLoadedXcodeFrameworks = NO;

@implementation FBDeviceControlFrameworkLoader

#pragma mark - Public

#pragma mark Essential Frameworks

+ (void)initializeEssentialFrameworks
{
  NSError *error = nil;
  id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
  BOOL success = [self loadEssentialFrameworks:logger error:&error];
  if (success) {
    return;
  }
  [logger.error logFormat:@"Failed to load the Essential frameworks for FBDeviceControl with error %@", error];
  abort();
}

+ (BOOL)loadEssentialFrameworks:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if (hasLoadedEssentialFrameworks) {
    return YES;
  }

  NSArray<FBWeakFramework *> *frameworks = @[
    FBWeakFramework.MobileDevice,
  ];
  BOOL result = [FBWeakFrameworkLoader loadPrivateFrameworks:frameworks logger:logger error:error];
  if (result) {
    [FBAMDevice loadFBAMDeviceSymbols];
    hasLoadedEssentialFrameworks = YES;
  }
  if (result && FBControlCoreGlobalConfiguration.debugLoggingEnabled) {
    [FBAMDevice enableDebugLogging];
  }
  return result;
}

#pragma mark Xcode Frameworks

+ (void)initializeXCodeFrameworks
{
  NSError *error = nil;
  id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
  BOOL success = [self loadXcodeFrameworks:logger error:&error];
  if (success) {
    return;
  }
  [logger.error logFormat:@"Failed to load the Xcode frameworks for FBDeviceControl with error %@", error];
  abort();
}

+ (BOOL)loadXcodeFrameworks:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if (hasLoadedXcodeFrameworks) {
    return YES;
  }

  NSArray<FBWeakFramework *> *frameworks = FBDeviceControlFrameworkLoader.privateFrameworks;

  if (![FBWeakFrameworkLoader loadPrivateFrameworks:frameworks logger:logger error:error]) {
    return NO;
  }
  if (![self confirmExistenceOfClasses:logger error:error]) {
    return NO;
  }
  if (![self initializePrincipalClasses:logger error:error]) {
    return NO;
  }
  hasLoadedXcodeFrameworks = YES;
  return YES;
}

+ (BOOL)confirmExistenceOfClasses:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSArray<NSString *> *classNames = @[
    @"DVTDeviceManager",
    @"DVTDeviceType",
    @"DVTiOSDevice",
    @"DVTPlatform",
    @"DVTDeviceType",
  ];
  NSMutableArray<NSString *> *unloadedClasses = [NSMutableArray array];
  for (NSString *className in classNames) {
    if (NSClassFromString(className)) {
      continue;
    }
    [logger.error logFormat:@"Expected %@ to be loaded, but it was not", className];
    [unloadedClasses addObject:className];
  }
  if (unloadedClasses.count > 0) {
    return [[FBDeviceControlError
      describeFormat:@"Expected %@ to be loaded, but they were not", [FBCollectionInformation oneLineDescriptionFromArray:unloadedClasses]]
      failBool:error];
  }
  return YES;
}

+ (BOOL)initializePrincipalClasses:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSError *innerError = nil;
  if (![objc_lookUpClass("IDEFoundationTestInitializer") initializeTestabilityWithUI:NO error:&innerError]) {
    return [[[FBDeviceControlError describe:@"Failed to initialize testability"] causedBy:innerError] failBool:error];
  }
  if (![objc_lookUpClass("DVTPlatform") loadAllPlatformsReturningError:&innerError]) {
    return [[[FBDeviceControlError describe:@"Failed to load all platforms"] causedBy:innerError] failBool:error];
  }
  if (![objc_lookUpClass("DVTPlatform") platformForIdentifier:@"com.apple.platform.iphoneos"]) {
    return [[[FBDeviceControlError describe:@"Platform 'com.apple.platform.iphoneos' hasn't been initialized yet"] causedBy:innerError] failBool:error];
  }
  if (![objc_lookUpClass("DVTDeviceType") deviceTypeWithIdentifier:@"Xcode.DeviceType.Mac"]) {
     return [[[FBDeviceControlError describe:@"Device Type 'Xcode.DeviceType.Mac' hasn't been initialized yet"] causedBy:innerError] failBool:error];
  }
  if (![objc_lookUpClass("DVTDeviceType") deviceTypeWithIdentifier:@"Xcode.DeviceType.iPhone"]) {
    return [[[FBDeviceControlError describe:@"Device Type 'Xcode.DeviceType.iPhone' hasn't been initialized yet"] causedBy:innerError] failBool:error];
  }
  [[objc_lookUpClass("DVTDeviceManager") defaultDeviceManager] startLocating];
  return YES;
}

+ (void)enableDVTDebugLogging
{
  [[objc_lookUpClass("DVTLogAspect") logAspectWithName:@"iPhoneSupport"] setLogLevel:10];
  [[objc_lookUpClass("DVTLogAspect") logAspectWithName:@"iPhoneSimulator"] setLogLevel:10];
  [[objc_lookUpClass("DVTLogAspect") logAspectWithName:@"DVTDevice"] setLogLevel:10];
  [[objc_lookUpClass("DVTLogAspect") logAspectWithName:@"Operations"] setLogLevel:10];
  [[objc_lookUpClass("DVTLogAspect") logAspectWithName:@"Executable"] setLogLevel:10];
  [[objc_lookUpClass("DVTLogAspect") logAspectWithName:@"CommandInvocation"] setLogLevel:10];
}

+ (BOOL)macOSVersionIsAtLeastSierra:(NSOperatingSystemVersion)macOSVersion
{
  return macOSVersion.minorVersion >= 12;
}

+ (BOOL)xcodeVersionIsAtLeast81:(NSDecimalNumber *)xcodeVersion
{
  NSDecimalNumber *xcode81 = [NSDecimalNumber decimalNumberWithString:@"8.1"];
  return [xcodeVersion compare:xcode81] != NSOrderedAscending;
}

+ (NSArray<FBWeakFramework *> *)privateFrameworkForMacOSVersion:(NSOperatingSystemVersion)macOSVersion
                                                   xcodeVersion:(NSDecimalNumber *)xcodeVersion {
  NSArray<FBWeakFramework *> *frameworks =
          @[
                  FBWeakFramework.DTXConnectionServices,
                  FBWeakFramework.DVTFoundation,
                  FBWeakFramework.IDEFoundation,
                  FBWeakFramework.IDEiOSSupportCore,
                  FBWeakFramework.IBAutolayoutFoundation,
                  FBWeakFramework.IDEKit,
                  FBWeakFramework.IDESourceEditor
          ];
  if ([FBDeviceControlFrameworkLoader macOSVersionIsAtLeastSierra:macOSVersion] &&
      [FBDeviceControlFrameworkLoader xcodeVersionIsAtLeast81:xcodeVersion]) {
    /*
     These frameworks are required by the DVTKitDFRSupport Xcode plug-in starting
     with Xcode >= 8.1 on macOS Sierra.  This plug-in is related to Touch Bar
     development.

     The DVTKitDFRSupport plug-in does not exist in Xcode 8.0 and any version
     of El Cap.

     The DVTKit.framework exists in Xcode >= 8.1 on El Cap and Sierra.

     The DFRSupportKit.framework only exists on Sierra in Xcode >= 8.1.
     */
    NSMutableArray *mutable = [NSMutableArray arrayWithArray:frameworks];
    [mutable addObject:FBWeakFramework.DFRSupportKit];
    [mutable addObject:FBWeakFramework.DVTKit];
    frameworks = [NSArray arrayWithArray:mutable];
  }
  return frameworks;
}

+ (NSArray<FBWeakFramework *> *)privateFrameworks
{
  NSDecimalNumber *xcodeVersion = FBControlCoreGlobalConfiguration.xcodeVersionNumber;
  NSOperatingSystemVersion macOSVersion = NSProcessInfo.processInfo.operatingSystemVersion;

  return [FBDeviceControlFrameworkLoader privateFrameworkForMacOSVersion:macOSVersion
                                                                  xcodeVersion:xcodeVersion];
}

@end
