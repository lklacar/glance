# Glance

A small native macOS image viewer inspired by Eye of GNOME. Open an image, scroll to zoom, and use the left/right arrow keys to browse the other images in its folder. Navigation wraps at either end.

Built with Swift, AppKit, Core Graphics, and Image I/O. No Electron, third-party runtime, network access, telemetry, or image-library installation is required.

Bundle identifier and Swift package name: `rs.qubit.glance`.

## Run

Requires **macOS 14 Sonoma or later**. The universal app runs on Apple Silicon and Intel.

Open `dist/Glance.app`, or copy it to Applications. Drop an image or folder onto the window, use **⌘O**, or use Finder’s **Open With → Glance**. To make it the default for a format, select an image in Finder, choose **Get Info → Open with → Glance → Change All**. The app does not change your file associations itself.

The local build is ad-hoc signed. A build intended for distribution to other Macs must be Developer ID signed and notarized; see [Release](#release).

## Controls

| Action | Control |
| --- | --- |
| Next / previous image, wrapping | Right / left arrow |
| First / last image | Home / End |
| Zoom at pointer | Scroll wheel or trackpad pinch |
| Pan | Drag, or Option/Shift + scroll |
| Zoom in / out | `+` / `−`, or toolbar |
| Fit to window | `0` / `⌘0`, or zoom percentage button |
| Actual pixels (Retina aware) | `1` / `⌘1` |
| Toggle fit / actual pixels | Double-click |
| Rotate view clockwise | `⌘R` |
| Pause / resume animation | Space |
| Start / stop five-second slideshow | `⇧⌘P`; Space on still images |
| Full screen | `⌃⌘F` |
| Stop slideshow / leave full screen | Escape |
| Image information | `⌘I` |
| Reveal file in Finder | `⇧⌘R` |
| Copy image file | `⌘C` |
| Open image or folder | `⌘O` |

Images appear in Finder-style natural filename order (`photo2` before `photo10`). Subfolders and hidden files are excluded, but an explicitly opened hidden or extensionless image remains viewable. Folder changes and replacements of the current image are detected automatically. Open Recent is available in the File menu. Closing the last window keeps the app available in the Dock.

Zoom and pan use Core Animation to scale the decoded image without repainting it for every input event. Wheel ticks and zoom buttons use short, display-synchronized transitions anchored at the pointer or window center. Trackpad scrolling and pinch gestures respond directly, including scrolling momentum. Reduce Motion disables the added transitions.

The viewer preloads up to **three images ahead and three behind**, including across the folder’s ends when navigation wraps. Ready images display directly from memory without a blank loading frame. Preloading runs on a separate background queue so it cannot queue ahead of a requested image. A **256 MiB cache budget** accounts for decoded pixels and source file sizes, preferring the closest images; decoder overhead and the displayed animation's frames are additional. Files are checked for edits, replacements, or removal before reuse. The cache clears on opening another image/folder or closing the window. Very large images or navigation faster than background decoding can still require a load.

## Formats and behavior

- JPEG (including CMYK), PNG (including transparency and APNG), GIF, TIFF, BMP, HEIC/HEIF, WebP, AVIF, JPEG 2000, JPEG XL, ICO, ICNS, PSD composites, TGA, OpenEXR, Radiance HDR, portable bitmap formats, and the camera RAW types supported by the installed macOS image decoders.
- SVG and PDF use macOS’s native vector rendering. SVG/PDF are rasterized to a bounded high-resolution preview.
- GIF, APNG, and animated WebP play automatically. Frames are decoded sequentially; the app does not retain an entire animation. Playback pauses when the window is minimized.
- Multipage TIFF/PDF, layered PSD files, and image collections display their first page or composite, rather than acting as page/layer editors.
- EXIF orientation is applied during decoding. Color profiles are handled through Core Graphics. This is a standard-range image viewer, not an HDR mastering or RAW development tool.
- Very large raster images use a preview capped at approximately **48 megapixels** and **16,384 pixels per edge**. The status bar identifies reduced previews. The displayed dimensions always describe the original image. Memory may also be used by macOS’s decoder; this cap is not a hard process-memory limit.
- New camera models, uncommon codec variants, and malformed files may not decode on every macOS version. Unsupported/corrupt files show an error without interrupting folder navigation.
- All operations are read-only. Rotation changes the view; it does not rewrite the file.

## Build

Install Apple’s Command Line Tools (`xcode-select --install`) or Xcode, with Swift 5.10 or later. No package downloads are needed.

```sh
Scripts/check.sh
Scripts/build.sh
open "dist/Glance.app"
```

`Scripts/build.sh` builds both architectures, generates the app icon, packages metadata, and verifies the signature. For a faster development build:

```sh
ARCHS=arm64 CONFIGURATION=debug Scripts/build.sh
```

Use `ARCHS=x86_64` on Intel. The build stages a new bundle separately before replacing the previous output.

## Verification

`Scripts/check.sh` runs an executable regression suite without requiring XCTest or full Xcode. It checks folder filtering and ordering, both wrap directions, empty/single-image folders, refresh/removal, pointer-anchored zoom, panning bounds, resize behavior, Retina scaling, EXIF orientation, image round trips, animation frames and timing, invalid input, vector fallback, and large-image downsampling.

It also runs `Scripts/check-window.sh`, which exercises the real window controller without showing test windows. These checks cover duplicate opens, metadata-only file changes, preloaded navigation, retaining the visible frame during a cold load, and reloading actual file edits/replacements without showing the empty state. Metadata such as Finder tags or last-opened attributes does not invalidate cached image pixels or trigger a reload. Zoom checks cover convergence, pointer anchoring, refresh-rate independence, direction reversal, rendered orientation in all four rotations, and reuse of image contents and checkerboard geometry across repeated zoom updates.

Small independently encoded format fixtures are committed under `Tests/Fixtures`. Regeneration is optional and uses `Scripts/make-fixtures.py` with Pillow 12.3 and WebP/AVIF support. Pillow is never needed to build or run the app.

Run verification from a normal macOS terminal: HEIC encoding and icon creation require access to system image services and can fail inside a restrictive execution sandbox.

[VALIDATION.md](VALIDATION.md) records what was actually checked and what still needs release testing. The included GitHub Actions workflow builds and checks the app when the repository is pushed; creating the workflow does not itself mean CI has run.

## Release

To distribute outside this Mac, provide an Apple **Developer ID Application** identity installed in Keychain and a `notarytool` Keychain profile. Xcode’s notarization tools and an Apple Developer account are required for this step.

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="your-notary-profile" \
Scripts/release.sh
```

The script runs checks, builds a hardened-runtime universal app, submits it to Apple for notarization, staples and validates the ticket, checks Gatekeeper acceptance, and produces a ZIP with a SHA-256 checksum. It stops on any failure. Credentials are not stored in the repository.

Without those credentials, `Scripts/build.sh` still produces a locally usable ad-hoc-signed app. Do not label that artifact as notarized.
