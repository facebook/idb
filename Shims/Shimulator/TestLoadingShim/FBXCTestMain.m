/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestMain.h"

#import <dlfcn.h>
#import <objc/runtime.h>

#import "FBRuntimeTools.h"
#import "XCTestPrivate.h"
#import "FBDebugLog.h"

#include "TargetConditionals.h"

#if TARGET_IPHONE_SIMULATOR
#import <UIKit/UIKit.h>
#elif TARGET_OS_MAC
#import <AppKit/AppKit.h>
#endif

static NSString *const ShimulatorStartXCTest = @"SHIMULATOR_START_XCTEST";

__attribute__((constructor)) static void XCTestMainEntryPoint()
{
  FBDebugLog(@"[XCTestMainEntryPoint] Running inside: %@", [[NSBundle mainBundle] bundleIdentifier]);
  if (!NSProcessInfo.processInfo.environment[ShimulatorStartXCTest]) {
    FBDebugLog(@"[XCTestMainEntryPoint] SHIMULATOR_START_XCTEST not present. Bye");
    return;
  }
  if ([[[NSBundle mainBundle] bundleIdentifier] hasPrefix:@"com.apple.test"]) {
    FBDebugLog(@"[XCTestMainEntryPoint] Looks like I am running inside Apple's test runner app. Bye");
    return;
  }
  FBDebugLog(@"[XCTestMainEntryPoint] Hold back, trying to load test bundle");
  if (!FBXCTestMain()) {
    NSLog(@"[XCTestMainEntryPoint] Loading XCTest bundle failed, bye");
    exit(1);
  }
  FBDebugLog(@"[XCTestMainEntryPoint] End of XCTestMainEntryPoint");
}

BOOL FBLoadXCTestIfNeeded()
{
  FBDebugLog(@"Env: %@", [NSProcessInfo processInfo].environment);

  if (objc_lookUpClass("XCTest")) {
    FBDebugLog(@"[XCTestMainEntryPoint] XCTest already loaded");
    return YES;
  }
  FBDebugLog(@"[XCTestMainEntryPoint] Loading XCTest framework");
  if (!dlopen("XCTest.framework/XCTest", RTLD_LAZY)) {
    FBDebugLog(@"[XCTestMainEntryPoint] Failed to load XCTest.framework. %@", [NSString stringWithUTF8String:dlerror()]);
    return NO;
  }
  FBDebugLog(@"[XCTestMainEntryPoint] XCTest loaded");
  return YES;
}

void FBDeployBlockWhenAppLoads(void(^mainBlock)()) {
#if TARGET_IPHONE_SIMULATOR
  NSString *notification = UIApplicationDidFinishLaunchingNotification;
#elif TARGET_OS_MAC
  NSString *notification = NSApplicationDidFinishLaunchingNotification;
#endif
  [[NSNotificationCenter defaultCenter]
   addObserverForName:notification
   object:nil
   queue:[NSOperationQueue mainQueue]
   usingBlock:^(NSNotification *note) {
     mainBlock();
   }];
}

BOOL FBXCTestMain()
{
  if (!FBLoadXCTestIfNeeded()) {
    exit(2);
  }
  NSString *configurationPath = NSProcessInfo.processInfo.environment[@"XCTestConfigurationFilePath"];
  if (!configurationPath) {
    NSLog(@"Failed to load XCTest as XCTestConfigurationFilePath environment variable is empty");
    return NO;
  }
  NSError *error;
  NSData *data = [NSData dataWithContentsOfFile:configurationPath options:0 error:&error];
  if (!data) {
    NSLog(@"Failed to load data of %@ due to %@", configurationPath, error);
    return NO;
  }
  XCTestConfiguration *configuration = nil;
  if([NSKeyedUnarchiver respondsToSelector:@selector(xct_unarchivedObjectOfClass:fromData:)]){
    configuration = (XCTestConfiguration *)[NSKeyedUnarchiver xct_unarchivedObjectOfClass:NSClassFromString(@"XCTestConfiguration") fromData:data];
  } else {
    configuration = [NSKeyedUnarchiver unarchiveObjectWithData:data];
  }
  if (!configuration) {
    NSLog(@"Loaded XCTestConfiguration is nil");
    return NO;
  }
  [configuration setAbsolutePath:configurationPath];

  NSURL *testBundleURL = configuration.testBundleURL;
  if (!testBundleURL) {
    NSLog(@"XCTestConfiguration has no test bundle URL value");
    return NO;
  }

  NSBundle *testBundle = [NSBundle bundleWithURL:testBundleURL];
  if (!testBundle) {
    NSLog(@"Failed to open test bundle from %@", testBundleURL);
    return NO;
  }

  if (![testBundle loadAndReturnError:&error]) {
    NSLog(@"Failed load test bundle with error: %@", error);
    return NO;
  }
  void (*XCTestMain)(XCTestConfiguration *) = (void (*)(XCTestConfiguration *))FBRetrieveXCTestSymbol("_XCTestMain");
  FBDeployBlockWhenAppLoads(^{
    CFRunLoopPerformBlock([NSRunLoop mainRunLoop].getCFRunLoop, kCFRunLoopCommonModes, ^{
      XCTestMain(configuration);
    });
  });
  return YES;
}
