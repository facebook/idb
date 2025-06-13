# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added `FBSimulatorSet.defaultSetWithLogger:error:` convenience method for creating a default simulator set
- Added Xcode 16+ compatibility for CoreSimulator API changes

### Fixed
- Fixed crash on Xcode 16+ due to removed `SimDeviceSet.defaultSet` selector
- Updated all Direct-FFI implementations to use runtime API detection for CoreSimulator
- Added proper error handling and logging for CoreSimulator API failures
- Added thread safety with dispatch_once for device set initialization
- Added autorelease pools for proper memory management in API calls
- Added fallback to default Xcode location when DEVELOPER_DIR is not set

### Changed
- `FBSimulatorControlConfiguration.defaultDeviceSetPath` now uses `SimServiceContext.sharedServiceContextForDeveloperDir:error:` on Xcode 16+
- Improved diagnostic logging to clearly indicate which CoreSimulator APIs were attempted