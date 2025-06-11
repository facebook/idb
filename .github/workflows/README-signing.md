# Code Signing Setup for idb_companion Releases

This document explains how to set up proper code signing for idb_companion releases.

## Current Setup

The workflows currently use ad-hoc signing (`--sign -`) which:
- Works for local testing
- Adds basic code signature
- Includes timestamp for signature validity
- Uses hardened runtime for the binary

## Setting Up Proper Code Signing

To use a proper Apple Developer certificate:

### 1. Export Your Certificate

```bash
# Export from Keychain on macOS
security export -t identities -f pkcs12 -o certificate.p12
```

### 2. Add to GitHub Secrets

Add these secrets to your repository:
- `APPLE_CERTIFICATE_BASE64`: Base64-encoded .p12 file
- `APPLE_CERTIFICATE_PASSWORD`: Password for the .p12 file
- `APPLE_DEVELOPER_ID`: Your Developer ID (e.g., "Developer ID Application: Your Name (TEAMID)")

```bash
# Convert certificate to base64
base64 -i certificate.p12 | pbcopy
```

### 3. Update Workflow

Replace the codesign step with:

```yaml
- name: Import certificate
  env:
    APPLE_CERTIFICATE_BASE64: ${{ secrets.APPLE_CERTIFICATE_BASE64 }}
    APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
  run: |
    # Create temporary keychain
    KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db
    KEYCHAIN_PASSWORD=$(openssl rand -base64 32)
    
    # Create keychain
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    
    # Import certificate
    echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode > certificate.p12
    security import certificate.p12 -P "$APPLE_CERTIFICATE_PASSWORD" \
      -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
    security list-keychain -d user -s "$KEYCHAIN_PATH"
    
    # Clean up
    rm certificate.p12

- name: Codesign frameworks and binary
  env:
    APPLE_DEVELOPER_ID: ${{ secrets.APPLE_DEVELOPER_ID }}
  run: |
    # Sign frameworks
    for framework in dist/Frameworks/*.framework; do
      codesign --force --deep --sign "$APPLE_DEVELOPER_ID" \
        --timestamp "$framework"
    done
    
    # Sign binary with hardened runtime
    codesign --force --sign "$APPLE_DEVELOPER_ID" \
      --timestamp --options runtime \
      --entitlements entitlements.plist \
      dist/bin/idb_companion
```

### 4. Notarization (Optional)

For distribution outside the App Store, you should notarize:

```yaml
- name: Notarize app
  env:
    APPLE_ID: ${{ secrets.APPLE_ID }}
    APPLE_PASSWORD: ${{ secrets.APPLE_PASSWORD }}
    APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
  run: |
    # Create zip for notarization
    ditto -c -k --keepParent dist/bin/idb_companion notarize.zip
    
    # Submit for notarization
    xcrun notarytool submit notarize.zip \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait
    
    # Staple the notarization
    xcrun stapler staple dist/bin/idb_companion
```

## Entitlements

Create `entitlements.plist` for hardened runtime:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
```