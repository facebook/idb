/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBControlCoreFixtures.h"

#import <FBControlCore/FBControlCore.h>

@implementation FBControlCoreFixtures

+ (NSString *)photo0Path
{
  return [[NSBundle bundleForClass:self] pathForResource:@"photo0" ofType:@"png"];
}

+ (NSString *)simulatorSystemLogPath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"simulator_system" ofType:@"log"];
}

+ (NSString *)treeJSONPath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"tree" ofType:@"json"];
}

+ (NSString *)assetsdCrashPathWithCustomDeviceSet
{
  return [[NSBundle bundleForClass:self] pathForResource:@"assetsd_custom_set" ofType:@"crash"];
}

+ (NSString *)appCrashPathWithDefaultDeviceSet
{
  return [[NSBundle bundleForClass:self] pathForResource:@"app_default_set" ofType:@"crash"];
}

+ (NSString *)appCrashPathWithCustomDeviceSet
{
  return [[NSBundle bundleForClass:self] pathForResource:@"app_custom_set" ofType:@"crash"];
}

+ (NSString *)agentCrashPathWithCustomDeviceSet
{
  return [[NSBundle bundleForClass:self] pathForResource:@"agent_custom_set" ofType:@"crash"];
}

@end

@implementation XCTestCase (FBControlCoreFixtures)

- (FBDiagnostic *)simulatorSystemLog
{
  return [[[FBDiagnosticBuilder builder]
    updatePath:FBControlCoreFixtures.simulatorSystemLogPath]
    build];
}

- (FBDiagnostic *)treeJSONDiagnostic
{
  return [[[FBDiagnosticBuilder builder]
    updatePath:FBControlCoreFixtures.treeJSONPath]
    build];
}

- (FBDiagnostic *)photoDiagnostic
{
  return [[[FBDiagnosticBuilder builder]
    updatePath:FBControlCoreFixtures.photo0Path]
    build];
}

- (FBProcessInfo *)launchCtlProcess
{
  return [[FBProcessFetcher new] processInfoFor:NSProcessInfo.processInfo.processIdentifier];
}

@end
