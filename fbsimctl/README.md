## fbsimctl

`fbsimctl` is a command line interface to the `FBSimulatorControl` Framework.

## FBSimulatorControlKit

`FBSimulatorControlKit` is a Framework that forms the core functionality in `fbsimctl`. It is created as an additional target so that the components of `fbsimctl` can be linked from the `FBSimulatorControlKitTests` target.

Unfortunately, there is an issue with Swift and it's usage with Frameworks that need to be overcome in order for `FBSimulatorControlKit` to be a dependency of `fbsimctl`. The [Swift Standard Libraries](https://developer.apple.com/library/ios/qa/qa1881/_index.html) end up being copied as `dylib`s for `FBSimulatorControlKit` and end up being embedded in the `fbsimctl` binary. This means that these symbols are exported and loaded twice.

This warning is harmless unless if `fbsimctl` is built at the same time as `FBSimulatorControlKit`. You can see this by looking at the 'Link' phase of `fbsimctl`, which features the following argument to `ld`:
`-L/Applications/xcode_7.2.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift_static/macosx -Xlinker -force_load_swift_libs -lswiftRuntime -lc++ -framework Foundation`

The path in the `XcodeDefault.toolchain` contains the static libs that get linked into the `fbsimctl` executable. Xcode doesn't provide an ability to configure the project to remove the static link of these libs, so they will get compiled in. Frameworks do not link these libraries statically, instead they will by dynamically linked. This can be seen in `FBSimulatorControlKit`'s `ld` command:
`-fobjc-link-runtime -L/Applications/xcode_7.2.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx`

