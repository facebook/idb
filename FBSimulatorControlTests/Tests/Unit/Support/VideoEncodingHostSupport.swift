/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import VideoToolbox

/// Probe for host hardware video encoding, memoized per process.
///
/// Several video tests drive a real VideoToolbox encode and wait on its output. Hosts without a
/// hardware H.264 encoder never produce output, so those tests skip instead of timing out.
/// Capability-gated, not runner-gated: any host with an encoder runs them, wherever it lives.
enum VideoEncodingHostSupport {
  static let supportsHardwareH264Encoding: Bool = {
    var encoderList: CFArray?
    guard VTCopyVideoEncoderList(nil, &encoderList) == noErr,
      let encoders = encoderList as? [[CFString: Any]]
    else {
      return false
    }
    return encoders.contains { encoder in
      let codec = (encoder[kVTVideoEncoderList_CodecType] as? NSNumber)?.uint32Value
      let hardware = (encoder[kVTVideoEncoderList_IsHardwareAccelerated] as? NSNumber)?.boolValue
      return codec == kCMVideoCodecType_H264 && hardware == true
    }
  }()
}
