/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 Enum for json keys in reporting
*/
typedef NSString *FBJSONKey NS_STRING_ENUM;

extern FBJSONKey const FBJSONKeyEventName;
extern FBJSONKey const FBJSONKeyEventType;
extern FBJSONKey const FBJSONKeyLevel;
extern FBJSONKey const FBJSONKeySubject;
extern FBJSONKey const FBJSONKeyTarget;
extern FBJSONKey const FBJSONKeyTimestamp;
extern FBJSONKey const FBJSONKeyCallArguments;
extern FBJSONKey const FBJSONKeyMessage;
extern FBJSONKey const FBJSONKeyDuration;
extern FBJSONKey const FBJSONKeyArgument;
extern FBJSONKey const FBJSONKeyArguments;

/**
 Enum for the possible event names
 */
typedef NSString *FBEventName NS_STRING_ENUM;

extern FBEventName const FBEventNameApprove;
extern FBEventName const FBEventNameClearKeychain;
extern FBEventName const FBEventNameClone;
extern FBEventName const FBEventNameConfig;
extern FBEventName const FBEventNameCreate;
extern FBEventName const FBEventNameDelete;
extern FBEventName const FBEventNameDiagnose;
extern FBEventName const FBEventNameDiagnostic;
extern FBEventName const FBEventNameFocus;
extern FBEventName const FBEventNameErase;
extern FBEventName const FBEventNameFailure;
extern FBEventName const FBEventNameHelp;
extern FBEventName const FBEventNameInstall;
extern FBEventName const FBEventNameKeyboardOverride;
extern FBEventName const FBEventNameLaunch;
extern FBEventName const FBEventNameLaunchXCTest;
extern FBEventName const FBEventNameList;
extern FBEventName const FBEventNameListApps;
extern FBEventName const FBEventNameListDeviceSets;
extern FBEventName const FBEventNameListen;
extern FBEventName const FBEventNameLog;
extern FBEventName const FBEventNameOpen;
extern FBEventName const FBEventNameQuery;
extern FBEventName const FBEventNameRecord;
extern FBEventName const FBEventNameRelaunch;
extern FBEventName const FBEventNameSearch;
extern FBEventName const FBEventNameServiceInfo;
extern FBEventName const FBEventNameSetLocation;
extern FBEventName const FBEventNameShutdown;
extern FBEventName const FBEventNameSignalled;
extern FBEventName const FBEventNameStateChange;
extern FBEventName const FBEventNameStream;
extern FBEventName const FBEventNameTap;
extern FBEventName const FBEventNameTerminate;
extern FBEventName const FBEventNameUninstall;
extern FBEventName const FBEventNameUpload;
extern FBEventName const FBEventNameWaitingForDebugger;
extern FBEventName const FBEventNameWatchdogOverride;
extern FBEventName const FBEventNameLaunched;
extern FBEventName const FBEventNameTerminated;
extern FBEventName const FBEventNameInvokeCall;

/**
 Enum for the possible event types
 */
typedef NSString *FBEventType NS_STRING_ENUM;

extern FBEventType const FBEventTypeStarted;
extern FBEventType const FBEventTypeEnded;
extern FBEventType const FBEventTypeDiscrete;
extern FBEventType const FBEventTypeSuccess;
extern FBEventType const FBEventTypeFailure;
