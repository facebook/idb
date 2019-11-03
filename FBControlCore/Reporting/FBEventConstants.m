/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBEventConstants.h"

FBJSONKey const FBJSONKeyEventName = @"event_name";
FBJSONKey const FBJSONKeyEventType = @"event_type";
FBJSONKey const FBJSONKeyLevel = @"level";
FBJSONKey const FBJSONKeySubject = @"subject";
FBJSONKey const FBJSONKeyTarget = @"target";
FBJSONKey const FBJSONKeyTimestamp = @"timestamp";
FBJSONKey const FBJSONKeyCallArguments = @"call_arguments";
FBJSONKey const FBJSONKeyMessage = @"message";
FBJSONKey const FBJSONKeyDuration = @"duration";
FBJSONKey const FBJSONKeyArgument = @"argument";
FBJSONKey const FBJSONKeyArguments = @"arguments";

FBEventName const FBEventNameApprove = @"approve";
FBEventName const FBEventNameClearKeychain = @"clear_keychain";
FBEventName const FBEventNameClone = @"clone";
FBEventName const FBEventNameConfig = @"config";
FBEventName const FBEventNameCreate = @"create";
FBEventName const FBEventNameDelete = @"delete";
FBEventName const FBEventNameDiagnose = @"diagnose";
FBEventName const FBEventNameDiagnostic = @"diagnostic";
FBEventName const FBEventNameFocus = @"focus";
FBEventName const FBEventNameErase = @"erase";
FBEventName const FBEventNameFailure = @"failure";
FBEventName const FBEventNameHelp = @"help";
FBEventName const FBEventNameInstall = @"install";
FBEventName const FBEventNameKeyboardOverride = @"keyboard_override";
FBEventName const FBEventNameLaunch = @"launch";
FBEventName const FBEventNameLaunchXCTest = @"launch_xctest";
FBEventName const FBEventNameList = @"list";
FBEventName const FBEventNameListApps = @"list_apps";
FBEventName const FBEventNameListDeviceSets = @"list_device_sets";
FBEventName const FBEventNameListen = @"listen";
FBEventName const FBEventNameLog = @"log";
FBEventName const FBEventNameOpen = @"open";
FBEventName const FBEventNameQuery = @"query";
FBEventName const FBEventNameRecord = @"record";
FBEventName const FBEventNameRelaunch = @"relaunch";
FBEventName const FBEventNameSearch = @"search";
FBEventName const FBEventNameServiceInfo = @"service_info";
FBEventName const FBEventNameSetLocation = @"set_location";
FBEventName const FBEventNameShutdown = @"shutdown";
FBEventName const FBEventNameSignalled = @"signalled";
FBEventName const FBEventNameStateChange = @"state";
FBEventName const FBEventNameStream = @"stream";
FBEventName const FBEventNameTap = @"tap";
FBEventName const FBEventNameTerminate = @"terminate";
FBEventName const FBEventNameUninstall = @"uninstall";
FBEventName const FBEventNameUpload = @"upload";
FBEventName const FBEventNameWaitingForDebugger = @"waiting_for_debugger";
FBEventName const FBEventNameWatchdogOverride = @"watchdog_override";
FBEventName const FBEventNameLaunched = @"launched";
FBEventName const FBEventNameTerminated = @"terminated";
FBEventName const FBEventNameInvokeCall = @"call";

FBEventType const FBEventTypeStarted = @"started";
FBEventType const FBEventTypeEnded = @"ended";
FBEventType const FBEventTypeDiscrete = @"discrete";
FBEventType const FBEventTypeSuccess = @"success";
FBEventType const FBEventTypeFailure = @"failure";
