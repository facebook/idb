/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <SimulatorApp/Mach.h>

struct unknown_point {
 float field1;
 float field2;
};

/**
* A GSEventRecord, which is used by 'Purple'.
*/
struct GSEventRecord {
 unsigned int field1;
 int field2;
 struct unknown_point field3;
 struct unknown_point field4;
 unsigned int field5;
 unsigned long long field6;
 unsigned int field7;
 int field8;
 int field9;
 unsigned int field10;
 char field11;
};

/**
* Purple Events as sent by -[SimDevice(GSEventsPrivate) sendPurpleEvent:]
*/
typedef struct {
 MachMessageHeader header;
 struct GSEventRecord message;
} PurpleMessage;
