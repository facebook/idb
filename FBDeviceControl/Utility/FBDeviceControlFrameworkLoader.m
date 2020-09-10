/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceControlFrameworkLoader.h"

#import <FBControlCore/FBControlCore.h>

#import <objc/runtime.h>

#import "FBDeviceControlError.h"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

static BOOL IsInitializing = NO;

static asl_object_t FBDeviceControlFrameworkLoader_asl_open(const char *ident, const char *facility, uint32_t opts)
{
  asl_object_t object = asl_open(ident, facility, opts);
  if (!IsInitializing) {
    return object;
  }
  asl_add_log_file(object, STDERR_FILENO);
  return object;
}

#ifndef DYLD_INTERPOSE

#define DYLD_INTERPOSE(_replacment,_replacee) \
   __attribute__((used)) static struct{ const void* replacment; const void* replacee; } _interpose_##_replacee \
            __attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacment, (const void*)(unsigned long)&_replacee };
DYLD_INTERPOSE(FBDeviceControlFrameworkLoader_asl_open, asl_open);

#endif

#pragma GCC diagnostic pop

@implementation FBDeviceControlFrameworkLoader

#pragma mark Initialziers

- (instancetype)init
{
  return [super initWithName:@"FBDeviceControl" frameworks:@[
    FBWeakFramework.MobileDevice,
  ]];
}

#pragma mark Public

- (BOOL)loadPrivateFrameworks:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if (self.hasLoadedFrameworks) {
    return YES;
  }
  BOOL result = [super loadPrivateFrameworks:logger error:error];
  if (result) {
    AMDCalls calls = FBDeviceControlFrameworkLoader.amDeviceCalls;
    IsInitializing = YES;
    calls.InitializeMobileDevice();
    IsInitializing = NO;
  }
  if (logger.level >= FBControlCoreLogLevelDebug) {
    [FBDeviceControlFrameworkLoader setDefaultLogLevel:9 logFilePath:@"/tmp/FBDeviceControl_MobileDevice.txt"];
  }
  return result;
}

+ (AMDCalls)amDeviceCalls
{
  static dispatch_once_t onceToken;
  static AMDCalls amDeviceCalls;
  dispatch_once(&onceToken, ^{
    [self populateMobileDeviceSymbols:&amDeviceCalls];
  });
  return amDeviceCalls;
}

#pragma mark Private

+ (void)populateMobileDeviceSymbols:(AMDCalls *)calls
{
  void *handle = [[NSBundle bundleWithIdentifier:@"com.apple.mobiledevice"] dlopenExecutablePath];
  calls->AMSEraseDevice = FBGetSymbolFromHandle(handle, "AMSEraseDevice");
  calls->AMSInitialize = FBGetSymbolFromHandle(handle, "AMSInitialize");
  calls->Connect = FBGetSymbolFromHandle(handle, "AMDeviceConnect");
  calls->CopyDeviceIdentifier = FBGetSymbolFromHandle(handle, "AMDeviceCopyDeviceIdentifier");
  calls->CopyErrorText = FBGetSymbolFromHandle(handle, "AMDCopyErrorText");
  calls->CopyProvisioningProfiles = FBGetSymbolFromHandle(handle, "AMDeviceCopyProvisioningProfiles");
  calls->CopyValue = FBGetSymbolFromHandle(handle, "AMDeviceCopyValue");
  calls->CreateDeviceList = FBGetSymbolFromHandle(handle, "AMDCreateDeviceList");
  calls->CreateHouseArrestService = FBGetSymbolFromHandle(handle, "AMDeviceCreateHouseArrestService");
  calls->Disconnect = FBGetSymbolFromHandle(handle, "AMDeviceDisconnect");
  calls->EnterRecovery = FBGetSymbolFromHandle(handle, "AMDeviceEnterRecovery");
  calls->InitializeMobileDevice = FBGetSymbolFromHandle(handle, "_InitializeMobileDevice");
  calls->InstallProvisioningProfile = FBGetSymbolFromHandle(handle, "AMDeviceInstallProvisioningProfile");
  calls->IsPaired = FBGetSymbolFromHandle(handle, "AMDeviceIsPaired");
  calls->LookupApplications = FBGetSymbolFromHandle(handle, "AMDeviceLookupApplications");
  calls->MountImage = FBGetSymbolFromHandle(handle, "AMDeviceMountImage");
  calls->NotificationSubscribe = FBGetSymbolFromHandle(handle, "AMDeviceNotificationSubscribe");
  calls->NotificationUnsubscribe = FBGetSymbolFromHandle(handle, "AMDeviceNotificationUnsubscribe");
  calls->Pair = FBGetSymbolFromHandle(handle, "AMDevicePair");
  calls->ProvisioningProfileCopyErrorStringForCode = FBGetSymbolFromHandle(handle, "MISCopyErrorStringForErrorCode");
  calls->ProvisioningProfileCopyPayload = FBGetSymbolFromHandle(handle, "MISProfileCopyPayload");
  calls->ProvisioningProfileCreateWithData = FBGetSymbolFromHandle(handle, "MISProfileCreateWithData");
  calls->ProvisioningProfileGetUUID = FBGetSymbolFromHandle(handle, "MISProvisioningProfileGetUUID");
  calls->RecoveryDeviceReboot = FBGetSymbolFromHandle(handle, "AMRecoveryModeDeviceReboot");
  calls->RecoveryModeDeviceSetAutoBoot = FBGetSymbolFromHandle(handle, "AMRecoveryModeDeviceSetAutoBoot");
  calls->Release = FBGetSymbolFromHandle(handle, "AMDeviceRelease");
  calls->RemoveProvisioningProfile = FBGetSymbolFromHandle(handle, "AMDeviceRemoveProvisioningProfile");
  calls->RestorableDeviceCopyBoardConfig = FBGetSymbolFromHandle(handle, "AMRestorableDeviceCopyBoardConfig");
  calls->RestorableDeviceCopyProductString = FBGetSymbolFromHandle(handle, "AMRestorableDeviceCopyProductString");
  calls->RestorableDeviceCopySerialNumber = FBGetSymbolFromHandle(handle, "AMRestorableDeviceCopySerialNumber");
  calls->RestorableDeviceCopyUserFriendlyName = FBGetSymbolFromHandle(handle, "AMRestorableDeviceCopyUserFriendlyName");
  calls->RestorableDeviceGetBoardID = FBGetSymbolFromHandle(handle, "AMRestorableDeviceGetBoardID");
  calls->RestorableDeviceGetChipID = FBGetSymbolFromHandle(handle, "AMRestorableDeviceGetChipID");
  calls->RestorableDeviceGetDeviceClass = FBGetSymbolFromHandle(handle, "AMRestorableDeviceGetDeviceClass");
  calls->RestorableDeviceGetECID = FBGetSymbolFromHandle(handle, "AMRestorableDeviceGetECID");
  calls->RestorableDeviceGetLocationID = FBGetSymbolFromHandle(handle, "AMRestorableDeviceGetLocationID");
  calls->RestorableDeviceGetProductType = FBGetSymbolFromHandle(handle, "AMRestorableDeviceGetProductType");
  calls->RestorableDeviceGetRecoveryModeDevice = FBGetSymbolFromHandle(handle, "AMRestorableDeviceGetRecoveryModeDevice");
  calls->RestorableDeviceGetState = FBGetSymbolFromHandle(handle, "AMRestorableDeviceGetState");
  calls->RestorableDeviceRegisterForNotifications = FBGetSymbolFromHandle(handle, "AMRestorableDeviceRegisterForNotifications");
  calls->RestorableDeviceUnregisterForNotifications = FBGetSymbolFromHandle(handle, "AMRestorableDeviceUnregisterForNotifications");
  calls->Retain = FBGetSymbolFromHandle(handle, "AMDeviceRetain");
  calls->SecureInstallApplication = FBGetSymbolFromHandle(handle, "AMDeviceSecureInstallApplication");
  calls->SecureStartService = FBGetSymbolFromHandle(handle, "AMDeviceSecureStartService");
  calls->SecureTransferPath = FBGetSymbolFromHandle(handle, "AMDeviceSecureTransferPath");
  calls->SecureUninstallApplication = FBGetSymbolFromHandle(handle, "AMDeviceSecureUninstallApplication");
  calls->ServiceConnectionGetSecureIOContext = FBGetSymbolFromHandle(handle, "AMDServiceConnectionGetSecureIOContext");
  calls->ServiceConnectionGetSocket = FBGetSymbolFromHandle(handle, "AMDServiceConnectionGetSocket");
  calls->ServiceConnectionInvalidate = FBGetSymbolFromHandle(handle, "AMDServiceConnectionInvalidate");
  calls->ServiceConnectionReceive = FBGetSymbolFromHandle(handle, "AMDServiceConnectionReceive");
  calls->ServiceConnectionReceiveMessage = FBGetSymbolFromHandle(handle, "AMDServiceConnectionReceiveMessage");
  calls->ServiceConnectionSend = FBGetSymbolFromHandle(handle, "AMDServiceConnectionSend");
  calls->ServiceConnectionSendMessage = FBGetSymbolFromHandle(handle, "AMDServiceConnectionSendMessage");
  calls->SetLogLevel = FBGetSymbolFromHandle(handle, "AMDSetLogLevel");
  calls->StartSession = FBGetSymbolFromHandle(handle, "AMDeviceStartSession");
  calls->StopSession = FBGetSymbolFromHandle(handle, "AMDeviceStopSession");
  calls->ValidatePairing = FBGetSymbolFromHandle(handle, "AMDeviceValidatePairing");
}

/**
 Sets the Default Log Level and File Path for MobileDevice.framework.
 Must be called before any MobileDevice APIs are called, as these values are read during Framework initialization.
 Logging goes via asl instead of os_log, so logging to a file path may be unpredicatable.

 @param level the Log Level to use.
 @param logFilePath the file path to log to.
 */
+ (void)setDefaultLogLevel:(int)level logFilePath:(NSString *)logFilePath
{
  NSNumber *levelNumber = @(level);
  CFPreferencesSetAppValue(CFSTR("LogLevel"), (__bridge CFPropertyListRef _Nullable)(levelNumber), CFSTR("com.apple.MobileDevice"));
  CFPreferencesSetAppValue(CFSTR("LogFile"), (__bridge CFPropertyListRef _Nullable)(logFilePath), CFSTR("com.apple.MobileDevice"));
}

@end
