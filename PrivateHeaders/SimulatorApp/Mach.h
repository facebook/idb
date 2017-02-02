/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

//#import <mach/mach.h>

#pragma pack(4)

/**
 Annotation of the mach_msg_header_t with offsets
 */
typedef struct {
  unsigned int msgh_bits; // 0x0
  unsigned int msgh_size; // 0x4
  unsigned int msgh_remote_port; // 0x8
  unsigned int msgh_local_port; // 0xc
  unsigned int msgh_voucher_port; // 0x10
  int msgh_id; // 0x14
} MachMessageHeader;

#pragma pack()
