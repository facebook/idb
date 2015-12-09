/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Upload.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBInteraction+Private.h"

#import <CoreSimulator/SimDevice.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorSession.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorInteraction+Convenience.h"
#import "FBSimulatorInteraction+Applications.h"
#import "FBProcessLaunchConfiguration+Helpers.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

static NSTimeInterval const UploadVideoDefaultWait = 15.0;

@implementation FBSimulatorInteraction (Upload)

- (instancetype)uploadPhotos:(NSArray *)photoPaths
{
  if (!photoPaths.count) {
    return [self succeed];
  }

  FBSimulator *simulator = self.simulator;

  return [self interact:^ BOOL (NSError **error, id _) {
    if (simulator.state != FBSimulatorStateBooted) {
      return [[FBSimulatorError describeFormat:@"Simulator must be booted to upload photos, is %@", simulator.device.stateString] failBool:error];
    }

    for (NSString *path in photoPaths) {
      NSURL *url = [NSURL fileURLWithPath:path];

      NSError *innerError = nil;
      if (![simulator.device addPhoto:url error:&innerError]) {
        return [[[FBSimulatorError describeFormat:@"Failed to upload photo at path %@", path] causedBy:innerError] failBool:error];
      }
    }
    return YES;
  }];
}

- (instancetype)uploadVideos:(NSArray *)videoPaths
{
  if (!videoPaths.count) {
    return [self succeed];
  }

  FBSimulator *simulator = self.simulator;
  return [self interact:^ BOOL (NSError **error, id _) {
    NSError *innerError = nil;
    const BOOL success = [FBSimulatorInteraction uploadVideos:videoPaths inSimulator:simulator error:&innerError];
    if (!success) {
      return [[[FBSimulatorError describeFormat:@"Failed to upload videos at paths %@", videoPaths]
        causedBy:innerError]
        failBool:error];
    }

    return YES;
  }];
}

#pragma mark Private

+ (BOOL)uploadVideos:(NSArray *)videoPaths inSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  if (!videoPaths.count) {
    return YES;
  }

  NSString *dcimPath = [simulator.dataDirectory stringByAppendingPathComponent:@"Media/DCIM/100APPLE"];
  NSArray *dcimPaths = ({
    NSError *innerError = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *subpaths = [fileManager subpathsOfDirectoryAtPath:dcimPath error:&innerError];
    if (!subpaths) {
      return [[[FBSimulatorError describeFormat:@"Couldn't read DCIM directory at path %@", dcimPath]
        causedBy:innerError]
        failBool:error];
    }
    [subpaths filteredArrayUsingPredicate:[self.class predicateForVideoFiles]];
  });

  NSString *joinedPaths = [videoPaths componentsJoinedByString:@":"];

  NSError *innerError = nil;
  FBSimulatorApplication *photosApp = [FBSimulatorApplication systemApplicationNamed:@"MobileSlideShow" error:&innerError];
  if (!photosApp) {
    return [[[FBSimulatorError describe:@"Could not get the MobileSlideShow App"] causedBy:innerError] failBool:error];
  }

  FBApplicationLaunchConfiguration *appLaunch = [[FBApplicationLaunchConfiguration
    configurationWithApplication:photosApp
    arguments:@[]
    environment:@{@"SHIMULATOR_UPLOAD_VIDEO" : joinedPaths}]
    injectingShimulator];

  if (![[simulator.interact launchApplication:appLaunch] performInteractionWithError:&innerError]) {
    return [[[FBSimulatorError describe:@"Couldn't launch MobileSlideShow to upload videos"] causedBy:innerError]
      failBool:error];
  }

  BOOL success = [self.class
    waitUntilFileCount:videoPaths.count
    addedToDirectory:dcimPath
    previousCount:dcimPaths.count
    error:error];

  if (![[simulator.interact killApplication:photosApp] performInteractionWithError:nil]) {
    return [[[FBSimulatorError describe:@"Couldn't kill MobileSlideShow after uploading videos"] causedBy:innerError] failBool:error];
  }

  return success;
}

+ (BOOL)waitUntilFileCount:(NSUInteger)fileCount addedToDirectory:(NSString *)directory previousCount:(NSUInteger)previousCount error:(NSError **)error
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  __block NSError *innerError = nil;
  const BOOL success = [NSRunLoop.currentRunLoop
    spinRunLoopWithTimeout:UploadVideoDefaultWait
    untilTrue:^ BOOL {
      NSArray *paths = [fileManager subpathsOfDirectoryAtPath:directory error:&innerError];
      paths = [paths filteredArrayUsingPredicate:[self.class predicateForVideoFiles]];
      return paths.count == fileCount + previousCount;
    }];

  if (!success) {
    return [[[FBSimulatorError describeFormat:@"Failed to upload videos"] causedBy:innerError] failBool:error];
  }
  
  return YES;
}

+ (NSPredicate *)predicateForVideoFiles
{
  return [NSPredicate predicateWithFormat:@"pathExtension IN %@", @[@"mp4"]];
}

@end
