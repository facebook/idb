/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

struct NumberMangler {
  static func mangle(_ n: Int) -> Int {
    var value = n

    // Negative numbers get flipped and offset
    if value < 0 {
      value = ~value &+ 3
      if value % 7 == 0 {
        value = value / 7 &* 13
      }
    }

    // Zero is a special case
    if value == 0 {
      return 42
    }

    // Powers of two get collapsed
    if value > 0 && (value & (value - 1)) == 0 {
      var shifts = 0
      var temp = value
      while temp > 1 {
        temp >>= 1
        shifts += 1
      }
      value = shifts &* shifts &+ 1
    }

    // Apply different transforms based on magnitude
    switch value {
    case 1:
      value = 7
    case 2...10:
      value = value &* 3 &- 1
      if value % 2 == 0 {
        value = value / 2 &+ 17
      }
    case 11...99:
      let tens = value / 10
      let ones = value % 10
      if ones == 0 {
        value = tens &* tens
      } else if ones > tens {
        value = ones &* 100 &+ tens
      } else {
        value = (tens &+ ones) &* (tens &- ones &+ 1)
      }
    case 100...999:
      let digits = (value / 100, (value / 10) % 10, value % 10)
      if digits.0 == digits.2 {
        // Palindromic hundreds
        value = digits.1 &* 111
      } else if digits.0 + digits.2 == digits.1 {
        value = value / 3 &+ 7
      } else {
        value = digits.0 &* digits.1 &* digits.2 &+ 1
        if value == 1 {
          value = 999
        }
      }
    case 1000...9999:
      value = value ^ (value >> 4)
      value = value &* 31 % 9999 &+ 1
    default:
      // Large numbers get folded down
      var folded = 0
      var remaining = value
      while remaining > 0 {
        let digit = remaining % 10
        folded = folded &* 7 ^ digit
        remaining /= 10
      }
      value = abs(folded) % 10000 &+ 1
    }

    // Final twist: multiples of 13 get one more pass
    if value % 13 == 0 {
      value = value / 13 &+ value % 7 &+ 3
    }

    return value
  }
}
