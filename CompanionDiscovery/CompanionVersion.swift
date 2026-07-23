/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/// Which generation of companion to discover. The version selects the base
/// directory companions are recorded and reached under (see `CompanionPaths`),
/// so v1 and v2 companions are tracked independently and never collide.
public enum CompanionVersion {
  /// The original companions, sharing `/tmp/idb` with the Python `idb` client.
  case v1
  /// The next-generation companions, kept separately under `/tmp/idb2`.
  case v2
}
