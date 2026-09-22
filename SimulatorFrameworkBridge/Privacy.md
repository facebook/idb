# Simulator privacy permissions

`privacy approve|revoke <bundleID> <camera|microphone|photos|contacts>...`
updates the selected application's permissions synchronously through the guest's
TCC daemon. Requests are validated before any changes. Repeated service names
are applied once. A failed operation exits nonzero with the service and bundle
identifier; earlier operations in the batch may already have succeeded.

The runtime binds `TCCAccessSetForBundleIdWithOptions` and
`TCCAccessResetForBundleIdWithOptions` from
`/System/Library/PrivateFrameworks/TCC.framework/TCC`. Both return a Boolean
answer from the daemon and borrow their CF arguments for the call. The service
names are `kTCCServiceCamera`, `kTCCServiceMicrophone`, `kTCCServicePhotos` and
`kTCCServiceAddressBook`.

Approval passes `auth_value: 2`, TCC's "allowed". Passing it explicitly is what
makes Photos report full authorization rather than a limited, user-chosen
selection. Revoke uses reset, restoring not-determined rather than recording a
denial.
Both operations pass the exported `kTCCSetNoKill` option to preserve the target
process. The symbol is a pointer to a CFStringRef variable, not the string itself.
Photos and Contacts may retain cached authorization after a reset until the app
is relaunched.

The guest embeds the scoped `com.apple.private.tcc.manager.access.modify` and
`com.apple.private.tcc.manager.access.delete` entitlements in its
`__TEXT,__entitlements` section. Code-signing entitlements alone do not provide
these capabilities to a simulator command-line executable.

The bindings and public app authorization results were verified on arm64 iOS
26.4 (23E254a) and 27.0 (24A434). The idb permission end-to-end tests read public
AVFoundation, Photos and Contacts authorization from the fixture application;
they also check selective resets, repeated operations and process survival.
