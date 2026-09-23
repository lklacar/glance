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
- Finder lists Glance under Open With, and opening a different WebP file there updates the viewer.

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

## Surrounding-image preloading update

All 19 regression check groups pass on Apple Silicon and in the optimized Intel executable under Rosetta. Five new groups verify wrapping and duplicate-free neighbor selection; byte-budget eviction that favors nearest images; invalidation after in-place edits, same-size atomic replacement, and deletion; reuse of the exact decoded image during warm navigation; and cache lookup timing.

On this Mac, a synthetic 2400 × 1600 PNG took approximately 9.06 ms to decode. A warm cache lookup, including a fresh filesystem version check, averaged 0.003 ms across 1,000 lookups. These are decoder/cache timings, not an end-to-end rendering benchmark or a guarantee for every file.

The window now uses cached images synchronously, preloads up to three neighbors in each direction on a separate serial background queue, and cancels outdated preload requests on navigation, folder changes, minimization, and window closure. The cache budget is 256 MiB for accounted pixel and source-file bytes; macOS decoder overhead is additional.

## Repeated-open flashing fix

A local filesystem trace confirmed that updating an extended attribute emits an attribute-change event without a data-write event. The previous monitor subscribed to those attribute changes and unconditionally cleared the cache/reloaded the image. The loading path also drew the empty-state illustration between decodes.

The monitor now subscribes to content writes, extension, deletion, rename, and revocation, excluding attribute-only changes. Cache fingerprints ignore metadata change time while retaining inode, size, and nanosecond modification time. Repeated opens of the same unchanged image are ignored. A load retains the previous frame until the new image is ready; an initial load uses a plain loading state instead of the welcome illustration.

All 21 core check groups pass locally. The added real-window-controller checks also pass without showing windows: metadata changes and duplicate opens preserve the image object and zoom; warmed navigation displays synchronously; cold loads never clear the displayed frame; atomic replacements and in-place edits reload without blank frames; corrupt replacements still report an error. `Scripts/check.sh` includes these controller checks so CI and release validation cover the regression.

## Smooth zoom update

All 24 core check groups and the window-controller checks pass locally. New checks verify that smoothed wheel zoom converges without overshooting, preserves pointer anchoring, responds consistently at simulated 60 Hz and 120 Hz, reverses immediately when requested, cancels cleanly, and bounds scroll input.

The canvas now holds decoded pixels in a Core Animation layer. Zoom and pan update layer geometry; the transparency checkerboard path is built only when the canvas changes size. Offscreen layer rendering matches the previous image orientation in all four rotations. A sequence of 1,000 zoom updates preserved the image contents and checkerboard path without marking the canvas for repaint. CPU submission averaged approximately 0.002 ms per update on this Mac; this is not a GPU frame-time or visible-frame-rate measurement.

Discrete wheel ticks and zoom buttons use a view-bound display link with a short time-based transition. Precise trackpad scrolling and pinch remain direct, scrolling momentum is accepted, and Reduce Motion bypasses transitions. Zoom updates only the percentage indicator instead of reformatting all image metadata. Physical trackpad behavior and sustained frame pacing on other hardware remain manual checks.

## Glance rename

Renamed the app, executable, Swift modules, menus, build/release artifacts, and documentation to Glance. The bundle identifier and Swift package name are `rs.qubit.glance`.

All 24 core check groups and the window/controller rendering checks pass after the rename. The optimized universal app builds for Apple Silicon and Intel; metadata, icon, strict code-signature verification, and dependency checks pass. The local bundle remains ad-hoc signed.

## Finder default-opening repair

The affected downloaded JPEG had both `com.apple.quarantine` and a `com.apple.LaunchServices.OpenWith` override pointing to `/Applications/Glance.app`; the format-wide JPEG default was still Preview. This matches Apple's documented quarantined-document/per-file-binding warning. Set the JPEG default to `rs.qubit.glance` and removed only that file's Open With override. Opening through the system default then displayed the affected 5911 × 3941 image in Glance, verified through the native window's accessibility state. The quarantine attribute was preserved. This required no app-code or signing change.

## Image context menu and large-photo caching

All 25 core check groups and the window/controller checks pass. The context menu reuses the existing image actions and is available only when an image is ready. Checks exercise menu action dispatch, zoom-mode checkmarks, rotation, navigation, slideshow state, animation pause/resume, and disabled actions in a single-image folder. Explicit opens and folder scans now normalize paths consistently, preventing duplicate entries when a folder is reached through a symlink.

The universal release build passes bundle verification and was installed at `/Applications/Glance.app`. A native right-click on a displayed image was verified to expose the new context menu in the running app.

Profiling a folder of four local photos reproduced cache thrashing: an approximately 170 MiB decoded neighbor was evicted under the old 256 MiB budget and decoded again on navigation. The cache now uses one-sixteenth of physical RAM, with a 256 MiB floor and 1 GiB ceiling. A three-large-JPEG regression fixture exceeds the old budget and verifies that navigation retains all three under the 512 MiB budget used for an 8 GiB Mac. Memory-pressure checks verify cache release without clearing the displayed frame and resumption of preloading after pressure subsides.

In the local four-photo comparison, repeated uncached switches took approximately 289–633 ms. With the revised budget, all measured switches hit the cache; after first presentation, repeated switches took approximately 11–14 ms. The first presentation of a cached large image still took up to 148 ms. These harness timings include main-thread navigation and a Core Animation flush, not a measurement of physical display latency or GPU frame time.
