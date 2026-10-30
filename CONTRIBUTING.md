# Contributing to conv3rt

Thanks for helping. A few rules keep this project honest and small.

## Ground rules

- **Never claim a capability you have not verified.** If a format is not tested,
  mark it `unverified`; do not present it as supported.
- **Read ≠ write.** Discover them separately.
- **Never label something lossless** unless the full pipeline is verified for
  that pair, with a test.
- **Do not silently drop content.** Animation frames, pages, metadata, alpha and
  bit depth must be preserved or reported.
- **No network.** Do not add URLSession/Network usage to the app or core.
- **Keep it small.** Prefer Apple frameworks. Weigh the bundle size of any
  dependency.

## Development

```sh
swift test          # run the suite
swift run conv3rt   # run the app
swift run conv3rt --dump-capabilities   # inspect live format support
```

## Adding a format or codec

1. Add or update the entry in `FormatCatalog` with correct `Evidence`.
2. If it needs a codec, pin an exact version, check the license (and its
   transitive dependencies), build it for both architectures, measure the size,
   and add a round-trip test.
3. Add a lossless round-trip test with known samples in `Tests/`.
4. Update `docs/FORMAT_MATRIX.md` (or regenerate with `--dump-matrix`).

## Pull requests

- Keep changes focused.
- Include a test for behavior changes.
- Update docs when behavior or support changes.
- Write UI strings and docs in English.

## Project layout

```text
Sources/Conv3rtCore/    UI-free core: capabilities, inspection, planning,
                        conversion, verification, file access, queue
Sources/Conv3rtApp/     SwiftUI app: window, file list, settings, Finder services
Tests/Conv3rtCoreTests/ the test suite
docs/                   format matrix and user-facing notes
```

## Release builds

Requires macOS 14+, the Xcode command line tools, and a Developer ID
Application identity for distribution.

```sh
swift test

# Package locally; distribution still needs Developer ID signing + notarization.
scripts/package.sh arm64 0.6.1 3     # Apple Silicon; version and monotonic build
scripts/package.sh x86_64 0.6.1 3    # Intel; same release build number

# Deterministic appcast fixtures; no production key or network.
bash scripts/test-appcast.sh
```

Optional codecs:

```sh
scripts/build-jxl.sh arm64   # builds libjxl; a few minutes per arch
scripts/build-avif.sh arm64  # builds libavif + libaom; slower
```

WebP writing works without either. Without libjxl, JPEG XL is read-only and its
tests are skipped.

### Update feeds

After Developer ID signing, approved notarization, stapling, and regeneration
of the final ZIP, prepare one architecture's feed:

```sh
# SPARKLE_ACCOUNT names the app-specific Keychain account used for this app.
swift scripts/generate-appcast.swift \
  --archive dist/conv3rt-0.6.1-apple-silicon/conv3rt-0.6.1-apple-silicon.zip \
  --asset-url https://github.com/onurergut/conv3rt/releases/download/v0.6.1/conv3rt-0.6.1-apple-silicon.zip \
  --arch arm64 --account "$SPARKLE_ACCOUNT"
```

The generator derives version, monotonic build number, and minimum macOS from
the archived plist, runs `scripts/verify-release.sh` against a staged copy, and
uses Sparkle 2.10.0's `sign_update` to sign and verify the final ZIP bytes. It
updates only the matching local feed. It performs no network requests, Apple
uploads, release creation, or push. Publish the exact signed ZIP without further
changes, then publish the matching feed. It cannot confirm that a remote asset
exists or matches those bytes. Intel uses `--arch x86_64` and the
`conv3rt-<version>-intel.zip` archive. Build numbers must increase.

## License

By contributing you agree your contributions are licensed under the MIT License
(`LICENSE`). Do not submit code you cannot license this way.
