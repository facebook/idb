/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

//#import <mach/mach.h>

#pragma pack(push, 4)

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

#pragma pack(pop)
