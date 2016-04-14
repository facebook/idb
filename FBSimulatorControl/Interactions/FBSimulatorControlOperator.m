/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlOperator.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

#import <IDEiOSSupportCore/DVTiPhoneSimulator.h>

#import <XCTestBootstrap/FBProductBundle.h>

@interface FBSimulatorControlOperator ()
@property (nonatomic, strong) DVTiPhoneSimulator *dvtDevice;
@property (nonatomic, strong) FBSimulator *simulator;
@end

@implementation FBSimulatorControlOperator

+ (instancetype)operatorWithSimulator:(FBSimulator *)simulator
{
  FBSimulatorControlOperator *operator = [self.class new];
  operator.dvtDevice = [NSClassFromString(@"DVTiPhoneSimulator") simulatorWithDevice:simulator.device];
  operator.simulator = simulator;
  return operator;
}


#pragma mark - FBDeviceOperator protocol

- (BOOL)waitForDeviceToBecomeAvailableWithError:(NSError **)error
{
  return YES;
}

- (BOOL)installApplicationWithPath:(NSString *)path error:(NSError **)error
{
  FBSimulatorApplication *application = [FBSimulatorApplication applicationWithPath:path error:error];
  if (![[self.simulator.interact installApplication:application] perform:error]) {
    return NO;
  }
  return YES;
}

- (BOOL)isApplicationInstalledWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return ([self.simulator installedApplicationWithBundleID:bundleID error:error] != nil);
}

- (FBProductBundle *)applicationBundleWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  FBSimulatorApplication *application = [self.simulator installedApplicationWithBundleID:bundleID error:error];
  if (!application) {
    return nil;
  }

  FBProductBundle *productBundle =
  [[[FBProductBundleBuilder builder]
    withBundlePath:application.path]
   build];

  return productBundle;
}

- (BOOL)launchApplicationWithBundleID:(NSString *)bundleID arguments:(NSArray *)arguments environment:(NSDictionary *)environment error:(NSError **)error
{
  FBSimulatorApplication *app = [self.simulator installedApplicationWithBundleID:bundleID error:error];
  if (!app) {
    return NO;
  }

  FBApplicationLaunchConfiguration *configuration = [FBApplicationLaunchConfiguration new];
  configuration.bundleName = app.binary.name;
  configuration.bundleID = bundleID;
  configuration.arguments = arguments;
  configuration.environment = environment;

  if (![[self.simulator.interact launchOrRelaunchApplication:configuration] perform:error]) {
    return NO;
  }
  return YES;
}

- (BOOL)killApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return [[self.simulator.interact terminateApplicationWithBundleID:bundleID] perform:error];
}

- (pid_t)processIDWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  FBSimulatorApplication *app = [self.simulator installedApplicationWithBundleID:bundleID error:error];
  return [[FBProcessFetcher new] subprocessOf:self.simulator.launchdSimProcess.processIdentifier withName:app.binary.name];
}


#pragma mark - Unsupported FBDeviceOperator protocol method

- (BOOL)cleanApplicationStateWithBundleIdentifier:(NSString *)bundleID error:(NSError **)error
{
  NSAssert(nil, @"cleanApplicationStateWithBundleIdentifier is not yet supported");
  return NO;
}

- (NSString *)applicationPathForApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSAssert(nil, @"applicationPathForApplicationWithBundleID is not yet supported");
  return nil;
}

- (BOOL)uploadApplicationDataAtPath:(NSString *)path bundleID:(NSString *)bundleID error:(NSError **)error
{
  NSAssert(nil, @"uploadApplicationDataAtPath is not yet supported");
  return NO;
}

- (NSString *)containerPathForApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSAssert(nil, @"containerPathForApplicationWithBundleID is not yet supported");
  return nil;
}

- (NSString *)consoleString
{
  NSAssert(nil, @"consoleString is not yet supported");
  return nil;
}

@end
