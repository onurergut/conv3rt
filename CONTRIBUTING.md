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

## License

By contributing you agree your contributions are licensed under the MIT License
(`LICENSE`). Do not submit code you cannot license this way.
