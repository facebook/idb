/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDevice.h"
#import "FBDevice+Private.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

#import <FBControlCore/FBControlCore.h>

#import "FBAMDevice.h"
#import "FBAMRestorableDevice.h"
#import "FBDeviceApplicationCommands.h"
#import "FBDeviceControlError.h"
#import "FBDeviceCrashLogCommands.h"
#import "FBDeviceDebuggerCommands.h"
#import "FBDeviceDiagnosticInformationCommands.h"
#import "FBDeviceEraseCommands.h"
#import "FBDeviceFileCommands.h"
#import "FBDeviceFileCommands.h"
#import "FBDeviceLocationCommands.h"
#import "FBDeviceLogCommands.h"
#import "FBDevicePowerCommands.h"
#import "FBDeviceScreenshotCommands.h"
#import "FBDeviceVideoRecordingCommands.h"
#import "FBDeviceXCTestCommands.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation FBDevice

@synthesize activationState = _activationState;
@synthesize allValues = _allValues;
@synthesize amDevice = _amDevice;
@synthesize architecture = _architecture;
@synthesize buildVersion = _buildVersion;
@synthesize calls = _calls;
@synthesize deviceType = _deviceType;
@synthesize extendedInformation = _extendedInformation;
@synthesize logger = _logger;
@synthesize name = _name;
@synthesize osVersion = _osVersion;
@synthesize productVersion = _productVersion;
@synthesize restorableDevice = _restorableDevice;
@synthesize state = _state;
@synthesize targetType = _targetType;
@synthesize udid = _udid;
@synthesize uniqueIdentifier = _uniqueIdentifier;

#pragma mark Initializers

- (instancetype)initWithSet:(FBDeviceSet *)set amDevice:(FBAMDevice *)amDevice restorableDevice:(FBAMRestorableDevice *)restorableDevice logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(amDevice || restorableDevice, @"An FBAMDevice or FBAMRestorableDevice must be provided");
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = set;
  _amDevice = amDevice;
  _restorableDevice = restorableDevice;
  [self cacheValuesFromInfo:(amDevice ?: restorableDevice) overwrite:YES];
  _logger = [logger withName:self.udid];
  _forwarder = [FBiOSTargetCommandForwarder forwarderWithTarget:self commandClasses:FBDevice.commandResponders statefulCommands:FBDevice.statefulCommands];

  return self;
}

#pragma mark FBiOSTarget

- (NSArray<Class> *)actionClasses
{
  return @[
    FBTestLaunchConfiguration.class,
  ];
}

- (dispatch_queue_t)workQueue
{
  return dispatch_get_main_queue();
}

- (dispatch_queue_t)asyncQueue
{
  return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
}

- (FBiOSTargetDiagnostics *)diagnostics
{
  return [[FBiOSTargetDiagnostics alloc] initWithStorageDirectory:self.auxillaryDirectory];
}

- (FBProcessInfo *)containerApplication
{
  return nil;
}

- (FBProcessInfo *)launchdProcess
{
  return nil;
}

- (NSString *)auxillaryDirectory
{
  NSString *cwd = NSFileManager.defaultManager.currentDirectoryPath;
  return [NSFileManager.defaultManager isWritableFileAtPath:cwd] ? cwd : @"/tmp";
}

- (FBiOSTargetScreenInfo *)screenInfo
{
  return nil;
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

#pragma mark FBDevice Class Properties

- (void)setAmDevice:(FBAMDevice *)amDevice
{
  _amDevice = amDevice;
  [self cacheValuesFromInfo:amDevice overwrite:YES];
}

- (FBAMDevice *)amDevice
{
  return _amDevice;
}

- (void)setRestorableDevice:(FBAMRestorableDevice *)restorableDevice
{
  _restorableDevice = restorableDevice;
  [self cacheValuesFromInfo:restorableDevice overwrite:NO];
}

- (FBAMRestorableDevice *)restorableDevice
{
  return _restorableDevice;
}

- (void)cacheValuesFromInfo:(id<FBiOSTargetInfo, FBDevice>)targetInfo overwrite:(BOOL)overwrite
{
  // Don't overwrite with nil values.
  if (!targetInfo) {
    return;
  }

  // These values should always be overwitten
  _calls = targetInfo.calls;
  _state = targetInfo.state;

  // Overwrite only if requested (i.e. if is the more information FBAMDevice)
  if (!_allValues || overwrite) {
    _allValues = targetInfo.allValues;
  }
  if (!_architecture || overwrite) {
    _architecture = targetInfo.architecture;
  }
  if (!_buildVersion || overwrite) {
    _buildVersion = targetInfo.buildVersion;
  }
  if (!_deviceType || overwrite) {
    _deviceType = targetInfo.deviceType;
  }
  if (!_extendedInformation || overwrite) {
    _extendedInformation = targetInfo.extendedInformation;
  }
  if (!_name || overwrite) {
    _name = targetInfo.name;
  }
  if (!_osVersion || overwrite) {
    _osVersion = targetInfo.osVersion;
  }
  if (_productVersion || overwrite) {
    _productVersion = targetInfo.productVersion;
  }
  if (!_targetType || overwrite) {
    _targetType = targetInfo.targetType;
  }
  if (!_udid || overwrite) {
    _udid = targetInfo.udid;
  }
  if (!_uniqueIdentifier || overwrite) {
    _uniqueIdentifier = targetInfo.uniqueIdentifier;
  }
  if (!_activationState || overwrite) {
    _activationState = targetInfo.activationState;
  }
}

#pragma mark FBDevice Protocol Implementation

- (AMDeviceRef)amDeviceRef
{
  FBAMDevice *amDevice = self.amDevice;
  if (!amDevice)  {
    return NULL;
  }
  return amDevice.amDeviceRef;
}

- (AMRecoveryModeDeviceRef)recoveryModeDeviceRef
{
  FBAMRestorableDevice *restorableDevice = self.restorableDevice;
  if (!restorableDevice) {
    return NULL;
  }
  return restorableDevice.recoveryModeDeviceRef;
}

#pragma mark FBDeviceCommands Protocol Implementation

- (FBFutureContext<id<FBDeviceCommands>> *)connectToDeviceWithPurpose:(NSString *)format, ...
{
  FBAMDevice *amDevice = self.amDevice;
  if (amDevice) {
    va_list args;
    va_start(args, format);
    NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    return [amDevice connectToDeviceWithPurpose:@"%@", string];
  }
  return [[FBDeviceControlError
    describeFormat:@"%@ fails when not AMDevice backed.", NSStringFromSelector(_cmd)]
    failFutureContext];
}

- (FBFutureContext<FBAMDServiceConnection *> *)startService:(NSString *)service
{
  FBAMDevice *amDevice = self.amDevice;
  if (amDevice) {
    return [amDevice startService:service];
  }
  return [[FBDeviceControlError
    describeFormat:@"%@ fails when not AMDevice backed.", NSStringFromSelector(_cmd)]
    failFutureContext];
}

- (FBFutureContext<FBDeviceLinkClient *> *)startDeviceLinkService:(NSString *)service
{
  FBAMDevice *amDevice = self.amDevice;
  if (amDevice) {
    return [amDevice startDeviceLinkService:service];
  }
  return [[FBDeviceControlError
    describeFormat:@"%@ fails when not AMDevice backed.", NSStringFromSelector(_cmd)]
    failFutureContext];
}

- (FBFutureContext<FBAFCConnection *> *)startAFCService:(NSString *)service
{
  FBAMDevice *amDevice = self.amDevice;
  if (amDevice) {
    return [amDevice startAFCService:service];
  }
  return [[FBDeviceControlError
    describeFormat:@"%@ fails when not AMDevice backed.", NSStringFromSelector(_cmd)]
    failFutureContext];
}

- (FBFutureContext<FBAFCConnection *> *)houseArrestAFCConnectionForBundleID:(NSString *)bundleID afcCalls:(AFCCalls)afcCalls
{
  FBAMDevice *amDevice = self.amDevice;
  if (amDevice) {
    return [amDevice houseArrestAFCConnectionForBundleID:bundleID afcCalls:afcCalls];
  }
  return [[FBDeviceControlError
    describeFormat:@"%@ fails when not AMDevice backed.", NSStringFromSelector(_cmd)]
    failFutureContext];
}

- (FBFuture<FBDeveloperDiskImage *> *)mountDeveloperDiskImage
{
  FBAMDevice *amDevice = self.amDevice;
  if (amDevice) {
    return [amDevice mountDeveloperDiskImage];
  }
  return [[FBDeviceControlError
    describeFormat:@"%@ fails when not AMDevice backed.", NSStringFromSelector(_cmd)]
    failFuture];
}

#pragma mark Forwarding

+ (NSArray<Class> *)commandResponders
{
  static dispatch_once_t onceToken;
  static NSArray<Class> *commandClasses;
  dispatch_once(&onceToken, ^{
    commandClasses = @[
      FBDeviceActivationCommands.class,
      FBDeviceApplicationCommands.class,
      FBDeviceCrashLogCommands.class,
      FBDeviceDebuggerCommands.class,
      FBDeviceDiagnosticInformationCommands.class,
      FBDeviceEraseCommands.class,
      FBDeviceFileCommands.class,
      FBDeviceLocationCommands.class,
      FBDeviceLogCommands.class,
      FBDevicePowerCommands.class,
      FBDeviceRecoveryCommands.class,
      FBDeviceScreenshotCommands.class,
      FBDeviceVideoRecordingCommands.class,
      FBDeviceXCTestCommands.class,
      FBInstrumentsCommands.class,
    ];
  });
  return commandClasses;
}

+ (NSSet<Class> *)statefulCommands
{
  // All commands are stateful
  return [NSSet setWithArray:self.commandResponders];
}

- (id)forwardingTargetForSelector:(SEL)selector
{
  // Try the underling FBAMDevice instance>
  if ([self.amDevice respondsToSelector:selector]) {
    return self.amDevice;
  }
  // Try the forwarder.
  id command = [self.forwarder forwardingTargetForSelector:selector];
  if (command) {
    return command;
  }
  // Nothing left.
  return [super forwardingTargetForSelector:selector];
}

- (BOOL)conformsToProtocol:(Protocol *)protocol
{
  if ([super conformsToProtocol:protocol]) {
    return YES;
  }
  if ([self.forwarder conformsToProtocol:protocol]) {
    return  YES;
  }

  return NO;
}

@end

#pragma clang diagnostic pop
