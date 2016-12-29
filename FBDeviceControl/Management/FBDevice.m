/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDevice.h"
#import "FBDevice+Private.h"

#import <IDEiOSSupportCore/DVTiOSDevice.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import <FBControlCore/FBControlCore.h>

#import "FBiOSDeviceOperator.h"
#import "FBDeviceVideoRecordingCommands.h"
#import "FBDeviceSet+Private.h"
#import "FBAMDevice.h"

_Nullable CFArrayRef (*_Nonnull FBAMDCreateDeviceList)(void);
int (*FBAMDeviceConnect)(CFTypeRef device);
int (*FBAMDeviceDisconnect)(CFTypeRef device);
int (*FBAMDeviceIsPaired)(CFTypeRef device);
int (*FBAMDeviceValidatePairing)(CFTypeRef device);
int (*FBAMDeviceStartSession)(CFTypeRef device);
int (*FBAMDeviceStopSession)(CFTypeRef device);
int (*FBAMDServiceConnectionGetSocket)(CFTypeRef connection);
int (*FBAMDServiceConnectionInvalidate)(CFTypeRef connection);
int (*FBAMDeviceSecureStartService)(CFTypeRef device, CFStringRef service_name, CFDictionaryRef userinfo, void *handle);
_Nullable CFStringRef (*_Nonnull FBAMDeviceGetName)(CFTypeRef device);
_Nullable CFStringRef (*_Nonnull FBAMDeviceCopyValue)(CFTypeRef device, _Nullable CFStringRef domain, CFStringRef name);
void (*FBAMDSetLogLevel)(int32_t level);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation FBDevice

@synthesize deviceOperator = _deviceOperator;
@synthesize recordingCommand = _recordingCommand;
@synthesize dvtDevice = _dvtDevice;

#pragma mark Initializers

- (instancetype)initWithSet:(FBDeviceSet *)set amDevice:(FBAMDevice *)amDevice logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = set;
  _amDevice = amDevice;
  _logger = [logger withPrefix:[NSString stringWithFormat:@"%@: ", amDevice.udid]];

  return self;
}

- (CFTypeRef)startTestManagerServiceWithError:(NSError **)error
{
  return [self.amDevice startTestManagerServiceWithError:error];
}

#pragma mark FBiOSTarget

- (NSString *)udid
{
  return self.amDevice.udid;
}

- (NSString *)name
{
  return self.amDevice.deviceName;
}

- (NSString *)auxillaryDirectory
{
  return [[[NSHomeDirectory()
    stringByAppendingPathComponent:@"Library"]
    stringByAppendingPathComponent:@"FBDeviceControl"]
    stringByAppendingPathComponent:self.udid];
}

- (FBSimulatorState)state
{
  return FBSimulatorStateUnknown;
}

- (FBiOSTargetType)targetType
{
  return FBiOSTargetTypeDevice;
}

- (FBProcessInfo *)containerApplication
{
  return nil;
}

- (FBProcessInfo *)launchdProcess
{
  return nil;
}

- (id<FBControlCoreConfiguration_Device>)deviceConfiguration
{
  return self.amDevice.deviceConfiguration;
}

- (id<FBControlCoreConfiguration_OS>)osConfiguration
{
  return self.amDevice.osConfiguration;
}

- (FBiOSTargetDiagnostics *)diagnostics
{
  return [[FBiOSTargetDiagnostics alloc] initWithStorageDirectory:self.auxillaryDirectory];
}

- (NSComparisonResult)compare:(id<FBiOSTarget>)target
{
  return FBiOSTargetComparison(self, target);
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [self debugDescription];
}

- (NSString *)debugDescription
{
  return [FBiOSTargetFormat.fullFormat format:self];
}

- (NSString *)shortDescription
{
  return [FBiOSTargetFormat.defaultFormat format:self];
}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  return [FBiOSTargetFormat.fullFormat extractFrom:self];
}

#pragma mark Properties

- (DVTiOSDevice *)dvtDevice
{
  if (_dvtDevice == nil) {
    _dvtDevice = [self.set dvtDeviceWithUDID:self.udid];
  }
  return _dvtDevice;
}

- (id<FBDeviceOperator>)deviceOperator
{
  if (_deviceOperator == nil) {
    _deviceOperator = [FBiOSDeviceOperator forDevice:self];
  }
  return _deviceOperator;
}

- (NSString *)modelName
{
  return self.amDevice.modelName;
}

- (NSString *)systemVersion
{
  return self.amDevice.systemVersion;
}

- (NSSet *)supportedArchitectures
{
  return self.dvtDevice.supportedArchitectures.set;
}

#pragma mark Forwarding

- (id)forwardingTargetForSelector:(SEL)selector
{
  // Try the Recording Command first, constructing a DeviceOperator is expensive.
  if ([self.recordingCommand respondsToSelector:selector]) {
    return self.recordingCommand;
  }
  if ([self.deviceOperator respondsToSelector:selector]) {
    return self.deviceOperator;
  }
  return [super forwardingTargetForSelector:selector];
}

- (FBDeviceVideoRecordingCommands *)recordingCommand
{
  if (!_recordingCommand) {
    _recordingCommand = [FBDeviceVideoRecordingCommands withDevice:self];
  }
  return _recordingCommand;
}

@end

#pragma clang diagnostic pop
