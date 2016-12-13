/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceVideoRecordingCommands.h"

#import <FBControlCore/FBControlCore.h>

#import "FBDeviceVideo.h"
#import "FBDevice.h"
#import "FBDevice+Private.h"
#import "FBDeviceControlError.h"

@interface FBDeviceVideoRecordingCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;
@property (nonatomic, strong, nullable, readwrite) FBDeviceVideo *video;

@end

@implementation FBDeviceVideoRecordingCommands

+ (instancetype)withDevice:(FBDevice *)device
{
  return [[self alloc] initWithDevice:device];
}

- (instancetype)initWithDevice:(FBDevice *)device
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  return self;
}

- (BOOL)startRecordingWithError:(NSError **)error
{
  NSError *innerError = nil;
  if (!self.video) {
    FBDiagnosticBuilder *logBuilder = [FBDiagnosticBuilder builderWithDiagnostic:self.device.diagnostics.video];
    NSString *filePath = logBuilder.createPath;
    FBDeviceVideo *video = [FBDeviceVideo videoForDevice:self.device filePath:filePath error:&innerError];
    if (!video) {
      return [FBDeviceControlError failBoolWithError:innerError errorOut:error];
    }
    self.video = video;
  }
  return [self.video startRecordingWithError:error];
}

- (BOOL)stopRecordingWithError:(NSError **)error
{
  if (!self.video) {
    return [[FBDeviceControlError
      describeFormat:@"There was no existing video instance for %@", self.device]
      failBool:error];
  }
  return [self.video stopRecordingWithError:error];
}

@end
