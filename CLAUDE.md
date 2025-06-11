# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Fork Purpose

This is a fork of Facebook's idb (iOS Development Bridge) maintained for the [arkavo-edge](https://github.com/arkavo-org/arkavo-edge) project. The fork enables:

- Controlled builds with bundled frameworks for self-contained deployment
- Custom packaging and static linking modifications
- Versioned releases for reproducible builds
- No dependency on user/system installations

## Project Overview

idb (iOS Development Bridge) is a command-line interface for automating iOS Simulators and Devices. It consists of:

1. **Companion Server** (macOS only) - Built with Objective-C/Swift frameworks that interface with Apple's private frameworks
2. **Python Client** - Cross-platform CLI that communicates with the companion via gRPC

## Key Architecture

### Framework Hierarchy
```
FBControlCore (base framework)
├── FBSimulatorControl (simulator control)
├── FBDeviceControl (device control) 
└── XCTestBootstrap (test execution)
```

### Client-Server Communication
- Protocol: gRPC (defined in `proto/idb.proto`)
- Server: `idb_companion` binary runs on macOS
- Client: Python package `fb-idb` can run anywhere

## Build Commands

### Building the Companion (macOS)
```bash
# Build all frameworks
./build.sh framework build

# Build idb_companion with frameworks
./idb_build.sh idb_companion build <output_directory>

# Using Xcode directly
xcodebuild -workspace idb_companion.xcworkspace -scheme idb_companion -sdk macosx build
```

### Building the Python Client
```bash
# Set version (required)
export FB_IDB_VERSION=1.0.0

# Install for development
pip install -e .

# Build distribution
python setup.py build
```

## Testing

### Objective-C/Swift Tests
```bash
# Test all frameworks
./build.sh framework test

# Test specific framework
xcodebuild -project FBSimulatorControl.xcodeproj -scheme FBControlCore -sdk macosx test
xcodebuild -project FBSimulatorControl.xcodeproj -scheme FBSimulatorControl -sdk macosx test
xcodebuild -project FBSimulatorControl.xcodeproj -scheme FBDeviceControl -sdk macosx test
xcodebuild -project FBSimulatorControl.xcodeproj -scheme XCTestBootstrap -sdk macosx test
```

### Python Tests
```bash
# Run Python tests (from project root)
python -m pytest idb/

# Run specific test module
python -m pytest idb/grpc/tests/hid_tests.py
```

## Development Workflow

### Making Changes to Frameworks
1. Edit Objective-C/Swift code in respective framework directories
2. Build with `./build.sh framework build` or Xcode
3. Run tests with `./build.sh framework test`

### Making Changes to Companion
1. Edit code in `CompanionLib/` or `idb_companion/`
2. Build with `./idb_build.sh idb_companion build`
3. Test by running the companion and connecting with client

### Making Changes to Python Client
1. Edit Python code in `idb/` directory
2. Test with `python -m pytest`
3. Install locally with `pip install -e .`

## Code Organization

### Companion Components
- `CompanionLib/`: Core companion functionality
- `IDBCompanionUtilities/`: Swift utilities (Atomic, TaskSelect, etc.)
- `PrivateHeaders/`: Apple private framework headers

### Python Client Components
- `idb/cli/`: Command-line interface implementation
- `idb/grpc/`: gRPC client and protocol implementation
- `idb/common/`: Shared utilities and types

### Key Design Patterns
- Commands are implemented as protocols (e.g., `FBApplicationCommands.h`)
- Each target type (simulator/device) implements these protocols
- Python client mirrors the command structure
- Async/await used throughout Python codebase

## Release Workflow for arkavo-edge

### GitHub Actions Workflows

#### Automatic Release (on tag push)
```bash
# Create and push a tag to trigger release
git tag 1.1.7-arkavo.1
git push origin 1.1.7-arkavo.1
```

#### Manual Release (via GitHub UI)
1. Go to Actions → Manual Release
2. Click "Run workflow"
3. Enter version (e.g., "1.1.7-arkavo.1")
4. Choose if pre-release

#### Build and Test (on every push)
- Automatically runs on push to main
- Builds all frameworks and companion
- Runs tests and uploads artifacts

### Local Build
```bash
# Build with bundled frameworks
./idb_build.sh idb_companion build ./dist

# Package for release (frameworks are in dist/Frameworks, binary in dist/bin)
cd dist
tar -czf idb_companion-1.1.7-arkavo.1.tar.gz bin Frameworks
```

### Release Structure
```
dist/
├── bin/
│   └── idb_companion
└── Frameworks/
    ├── FBControlCore.framework/
    ├── FBSimulatorControl.framework/
    ├── FBDeviceControl.framework/
    └── XCTestBootstrap.framework/
```

### Modifications for Self-Contained Deployment
- Frameworks bundled with binary (no system install required)
- rpath modifications for loading frameworks from relative paths
- Static linking where possible to reduce dependencies
- Automatic codesigning in CI/CD pipeline
- ARM64-only builds (no x86_64 support)

## Common Issues

### Build Failures
- Ensure Xcode and Command Line Tools are installed
- Private frameworks are referenced but not distributed
- Some features require specific iOS/macOS versions

### gRPC Generation
- Proto files are compiled during Python build via `setup.py`
- Generated files go to `build/lib/idb/grpc/`
- Custom protoc compiler template handles import paths

### Framework Loading
- Use `install_name_tool` to fix framework rpaths if needed
- Ensure frameworks are codesigned for distribution
- Check with `otool -L` that all dependencies are resolved