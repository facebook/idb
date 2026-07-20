/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFourCharCode.h"

NSString *FBStringFromFourCharCode(OSType code)
{
  uint8_t bytes[4] = {
    (uint8_t)((code >> 24) & 0xff),
    (uint8_t)((code >> 16) & 0xff),
    (uint8_t)((code >> 8) & 0xff),
    (uint8_t)(code & 0xff),
  };
  BOOL allPrintableASCII = YES;
  for (size_t i = 0; i < sizeof(bytes); i++) {
    if (bytes[i] < 0x20 || bytes[i] > 0x7e) {
      allPrintableASCII = NO;
      break;
    }
  }
  if (allPrintableASCII) {
    NSString *string = [[NSString alloc] initWithBytes:bytes length:sizeof(bytes) encoding:NSASCIIStringEncoding];
    if (string) {
      return string;
    }
  }
  return [NSString stringWithFormat:@"0x%08x", code];
}
