/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
