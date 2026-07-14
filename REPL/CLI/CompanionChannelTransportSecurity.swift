/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery
import GRPC
import NIOSSL

/// The gRPC transport security for a companion connection. When `tls` is
/// `.metaIdentity`, a TCP companion whose Meta identity is available uses TLS —
/// presenting the client identity without verifying the peer, matching
/// `CompanionClient`. A Unix domain socket, a `tls` of `.disabled` (`--plaintext`),
/// or a missing identity is plaintext.
func channelTransportSecurity(
  for address: CompanionAddress,
  tls: CompanionClientTLS
) throws -> GRPCChannelPool.Configuration.TransportSecurity {
  guard
    let identity = replClientTLSIdentity(
      for: address, tls: tls, provider: CompanionTLS.provider)
  else {
    return .plaintext
  }
  let certificateChain = try NIOSSLCertificate.fromPEMFile(identity.certificateChainPath)
    .map { NIOSSLCertificateSource.certificate($0) }
  return .tls(
    .makeClientConfigurationBackedByNIOSSL(
      certificateChain: certificateChain,
      privateKey: .file(identity.privateKeyPath),
      certificateVerification: .none))
}
