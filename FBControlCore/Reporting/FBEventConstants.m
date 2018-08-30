/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBEventConstants.h"

FBJSONKey const FBJSONKeyEventName = @"event_name";
FBJSONKey const FBJSONKeyEventType = @"event_type";
FBJSONKey const FBJSONKeyLevel = @"level";
FBJSONKey const FBJSONKeySubject = @"subject";
FBJSONKey const FBJSONKeyTarget = @"target";
FBJSONKey const FBJSONKeyTimestamp = @"timestamp";

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
FBEventName const FBEventNameLaunchAgent = @"agentlaunch";
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

FBEventType const FBEventTypeStarted = @"started";
FBEventType const FBEventTypeEnded = @"ended";
FBEventType const FBEventTypeDiscrete = @"discrete";
