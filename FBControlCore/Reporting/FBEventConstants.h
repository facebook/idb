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
 Enum for the possible event types
 */
typedef NSString *FBEventType NS_STRING_ENUM;

extern FBEventType const FBEventTypeStarted;
extern FBEventType const FBEventTypeEnded;
extern FBEventType const FBEventTypeDiscrete;
extern FBEventType const FBEventTypeSuccess;
extern FBEventType const FBEventTypeFailure;
