# Validation record

Validated locally on macOS 15.7.4, Apple Silicon, using Apple Swift 6.1.2 and a Retina display.

## Automated checks

`Scripts/check.sh`: **14 check groups passed; zero failures.** The same 14 groups also passed in the optimized Intel executable under Rosetta.

- Natural filename ordering, uppercase extensions, hidden files, non-image files, and directories with image-like names.
- Forward/backward wrapping, large movement deltas, empty and single-image catalogs.
- Preserving selection during a refresh and choosing a replacement after removal.
- Pointer-anchored zoom, pan bounds, fit on resize, manual zoom on resize, and Retina fit scaling.
- Encode/decode round trips for PNG, JPEG, TIFF, GIF, BMP, JPEG 2000, HEIC, and ICO.
- EXIF orientation and rotated dimensions.
- GIF frame decoding and duration.
- Corrupt, missing, and non-file URL rejection.
- SVG and PDF rendering.
- Major image extension discovery.
- Independently encoded fixtures: 16-bit TIFF, CMYK JPEG, transparent PNG, GIF, APNG, animated WebP, PSD composite, PDF, multipage TIFF, AVIF, JPEG 2000, PPM, TGA, WebP, and SVG.
- A 54-megapixel TIFF reduced to the configured preview budget while retaining original dimensions in metadata.

## Live app checks

Performed against the native window and release app using macOS UI automation:

- Open a file through the native file chooser.
- Decode and display AVIF, WebP, PNG, JPEG, GIF, and SVG.
- Six consecutive right-arrow changes from image 7/12 wrap to image 1/12; left arrow then wraps to 12/12.
- Scroll-wheel zoom changes the displayed scale; keyboard zoom and Retina-aware actual pixels work.
- Rotate the view clockwise. A discovered drawing-over-toolbar bug was repaired and visually rechecked in the release build.
- Enter full screen and leave using Escape.
- Display useful image information.
- Recover from a corrupt PNG using the right arrow.
- Add an image to the active folder: the count changes from 4 to 5 without losing the selected image.
- Remove/rename the current file: the viewer advances to the next image and updates the count.
- Show in Finder selects the correct file.
- Finder lists Photo Viewer under Open With, and opening a different WebP file there updates the viewer.

Panning geometry and animated timing/frame decoding are covered by automated checks. Full end-to-end drag-and-drop, trackpad pinch gestures, VoiceOver interaction, and long-duration slideshow/animation soak testing have not been certified.

## Release artifact

- Universal `arm64` + `x86_64` optimized binary built successfully.
- App bundle metadata and privacy manifest pass `plutil` validation.
- App icon generated and included.
- Ad-hoc hardened-runtime code signature passes strict bundle verification.
- No Homebrew or developer-local dynamic-library dependency.
- Native app bundle is approximately 1 MB before ZIP compression.

## Remaining distribution gates

This record is evidence of the checks above, not a guarantee that all bugs or all codec variants have been tested.

- No Developer ID signing identity is available in the build environment. The local artifact is **not notarized**. Use `Scripts/release.sh` with the owner's Developer ID and Keychain notarization profile before public distribution.
- The Intel executable was cross-compiled and its regression checks passed under Rosetta, but the app was not tested on physical Intel hardware.
- macOS 14 is the deployment target; this session ran on macOS 15.7.4. Test on macOS 14 and the other supported OS releases before a public release.
- Real camera RAW samples from different camera models, JPEG XL, OpenEXR/HDR variants, and ICC color accuracy against calibrated references were not exhaustively tested. Those rely on the installed macOS decoders and documented preview behavior.
- GitHub Actions configuration is included but has not run in this local-only session.
