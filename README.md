<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/header/glow.svg?title=Glance&amp;subtitle=Open.+Scroll.+Next.&amp;theme=blue&amp;mode=dark&amp;width=1200&amp;height=260&amp;align=center&amp;font=geist&amp;border=false&amp;watermark=false" />
    <img src="https://shieldcn.dev/header/glow.svg?title=Glance&amp;subtitle=Open.+Scroll.+Next.&amp;theme=blue&amp;mode=light&amp;width=1200&amp;height=260&amp;align=center&amp;font=geist&amp;border=false&amp;watermark=false" alt="Glance — Open. Scroll. Next." width="100%" />
  </picture>
</p>

<p align="center">
  <strong>A native macOS image viewer, inspired by Eye of GNOME and the classic Windows Photo Viewer.</strong><br />
  Open an image. Scroll to zoom. Use the arrow keys to explore its folder.
</p>

<p align="center">
  <a href="#installation">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/macOS-14%2B-2563eb.svg?variant=secondary&amp;mode=dark&amp;font=geist&amp;logo=apple" />
      <img src="https://shieldcn.dev/badge/macOS-14%2B-2563eb.svg?variant=secondary&amp;mode=light&amp;font=geist&amp;logo=apple" alt="macOS 14 or later" />
    </picture>
  </a>
  <a href="#installation">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/Universal-Apple%20Silicon%20%2B%20Intel-2563eb.svg?variant=secondary&amp;mode=dark&amp;font=geist&amp;logo=false" />
      <img src="https://shieldcn.dev/badge/Universal-Apple%20Silicon%20%2B%20Intel-2563eb.svg?variant=secondary&amp;mode=light&amp;font=geist&amp;logo=false" alt="Universal app for Apple Silicon and Intel" />
    </picture>
  </a>
  <a href="#development">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/Swift-5.10%2B-2563eb.svg?variant=secondary&amp;mode=dark&amp;font=geist&amp;logo=swift" />
      <img src="https://shieldcn.dev/badge/Swift-5.10%2B-2563eb.svg?variant=secondary&amp;mode=light&amp;font=geist&amp;logo=swift" alt="Built with Swift 5.10 or later" />
    </picture>
  </a>
  <a href="#privacy">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/Privacy-Offline-2563eb.svg?variant=secondary&amp;mode=dark&amp;font=geist&amp;logo=false" />
      <img src="https://shieldcn.dev/badge/Privacy-Offline-2563eb.svg?variant=secondary&amp;mode=light&amp;font=geist&amp;logo=false" alt="Works offline" />
    </picture>
  </a>
</p>

<p align="center">
  <a href="#installation">Install</a> ·
  <a href="#controls">Controls</a> ·
  <a href="#supported-formats">Formats</a> ·
  <a href="#development">Development</a> ·
  <a href="https://github.com/lklacar/glance/issues">Report an issue</a>
</p>

---

I couldn't find a good fucking photo viewer for macOS, so I built one.

Glance takes its cues from **Eye of GNOME** and the **old-school Windows Photo Viewer**: open an image, scroll to zoom, and use the arrow keys to move through its folder. Simple, familiar, and fast.

Glance opens images directly from your folders. There is no library to import, account to create, or catalog to maintain.

- **Browse with the arrow keys.** Move through images in natural filename order, wrapping from the last image back to the first.
- **Zoom smoothly.** Scroll or pinch around the pointer, drag to pan, and switch between fit-to-window and actual pixels.
- **Keep moving.** Glance preloads up to three images in each direction, including across the ends of a folder.
- **View stills and animation.** Open everyday image formats, play GIF/APNG/WebP animations, and inspect SVGs and PDFs.
- **Stay in sync.** Folder changes and edits to the current image appear automatically.
- **Leave originals untouched.** Rotation changes the view; Glance does not rewrite your images.

## Installation

**Requires macOS 14 Sonoma or later.** The default build produces a universal app for Apple Silicon and Intel.

There is no published release yet. Build from source with Xcode or Apple's Command Line Tools and **Swift 5.10 or later**:

```sh
git clone https://github.com/lklacar/glance.git
cd glance
Scripts/build.sh
open dist/Glance.app
```

Repository access is required to clone. The app has no third-party package dependencies. If the build tools are missing, install them with `xcode-select --install`.

Drag `dist/Glance.app` into **Applications** to keep it installed. If you already have a local build ZIP, extract it and move `Glance.app` into Applications.

> **Local build status:** current builds are ad-hoc signed, not notarized by Apple. Developer ID signing and notarization are required before public distribution. See [Release builds](#release-builds).

## Getting started

Open an image with **⌘O**, drop an image or folder onto Glance, or choose **Open With → Glance** in Finder. Press **← / →** to browse and scroll to zoom.

Images are sorted as Finder sorts filenames: `photo2` comes before `photo10`. Browsing stays within the current folder and excludes subfolders and hidden files. An explicitly opened hidden or extensionless image can still be displayed.

Use **File → Open Recent** to return to a recent image. Closing the window keeps Glance in the Dock; **⌘Q** quits.

### Make Glance your default viewer

1. Select an image in Finder and press **⌘I** to open Get Info.
2. Under **Open with**, choose **Glance**.
3. Click **Change All…** and confirm.

Repeat for each format you want Glance to open by default. Use **Change All…** instead of setting an individual downloaded file to **Always Open With**; see [Troubleshooting](#troubleshooting). Glance itself does not change file associations.

## Controls

| Action | Shortcut or gesture |
| :--- | :--- |
| Previous / next image | **← / →**; wraps at both ends |
| First / last image | **Home / End** |
| Zoom around the pointer | Scroll wheel or trackpad pinch |
| Pan | Drag, or **Option / Shift + scroll** |
| Zoom in / out | **+ / −**, or toolbar buttons |
| Fit to window | **0 / ⌘0**, or click the zoom percentage |
| Actual pixels, Retina aware | **1 / ⌘1** |
| Toggle fit / actual pixels | Double-click |
| Rotate view clockwise | **⌘R** |
| Pause / resume animation | **Space** |
| Toggle five-second slideshow | **⇧⌘P**; **Space** on still images |
| Toggle full screen | **⌃⌘F** |
| Stop slideshow / leave full screen | **Escape** |
| Image information | **⌘I** |
| Reveal file in Finder | **⇧⌘R** |
| Copy image file | **⌘C** |
| Open image or folder | **⌘O** |

## Supported formats

Glance uses macOS Image I/O and AppKit. Decoder availability depends on the installed macOS version, camera model, and file variant.

| Category | Formats and behavior |
| :--- | :--- |
| Everyday images | JPEG, PNG, TIFF, BMP, HEIC/HEIF, WebP, AVIF |
| Animation | GIF, APNG, animated WebP; playback starts automatically |
| Icons and additional raster formats | ICO, ICNS, JPEG 2000, TGA, portable bitmap formats |
| Design files and documents | PSD composite; SVG and PDF rendered as raster previews |
| System-dependent formats | JPEG XL, OpenEXR, Radiance HDR, and camera RAW formats supported by macOS, including DNG, CR2/CR3, NEF, ARW, ORF, RAF, RW2, PEF, and SRW |

EXIF orientation is applied during decoding, and Core Graphics handles color profiles. Multipage TIFF/PDF files, layered PSD files, and image collections show the first page or composite. Glance displays standard-range previews; it is not a RAW developer or HDR mastering tool.

Very large raster images are downsampled to approximately **48 megapixels**, with a maximum edge of **16,384 pixels**. The status bar identifies reduced previews and retains the original raster dimensions. Unsupported or damaged files show an error while leaving folder navigation available.

<details>
<summary><strong>Performance and rendering details</strong></summary>

Zoom and pan update Core Animation layers without repainting the decoded image for every input event. Wheel ticks and zoom buttons use short, display-synchronized transitions. Precise trackpad scrolling and pinch respond directly; Reduce Motion disables the added transitions.

A separate background queue preloads up to three images before and after the current image. The cache favors nearby images within a **256 MiB budget** for accounted decoded pixels and source-file sizes. Decoder overhead and animation frames use additional memory, so this is not a total process-memory limit. Large images or rapid navigation can still require a load.

Cached files are checked for edits, replacement, and removal before reuse. An uncached navigation retains the previous frame until the next one is ready. GIF, APNG, and WebP frames decode sequentially, and animation pauses when the window is minimized.

SVG/PDF previews are rasterized at a bounded resolution. Raster and vector previews never modify the original file.

</details>

## Privacy

The app works locally. It has no accounts, telemetry, network requests, or third-party runtime dependencies. Your images stay on your Mac, and viewing or rotating them does not change their contents.

The banner and badges in this README are served by [shieldcn](https://shieldcn.dev/); they are not part of the app.

## Troubleshooting

### Finder says an image cannot be verified

A downloaded file with a file-specific **Open With** override can trigger a macOS warning against the image itself. [Apple documents this behavior](https://developer.apple.com/forums/thread/795994).

Set the default for the entire format using **Get Info → Open with → Glance → Change All…**. If the affected file still has a conflicting per-file association, that override must be cleared. You can also open the image from inside Glance using **File → Open**. Disabling Gatekeeper or removing download quarantine is not necessary to repair the association.

### An image will not open, or looks different from its editor

Check whether your macOS version supports the file's codec or camera model. Glance shows a first page, composite, or bounded preview where appropriate; it does not reproduce an editor's layers, RAW adjustments, or HDR workflow. If opening fails, you can still browse to the next image.

### HEIC checks or icon generation fail during a build

Run the build and checks from a normal macOS terminal. These operations need access to macOS image services and can fail in a restricted execution sandbox.

## Development

Glance is built with **Swift, AppKit, Core Graphics, Core Animation, and Image I/O**. Its bundle identifier and Swift package name are `rs.qubit.glance`.

```sh
# Run core, window-controller, and rendering regression checks.
Scripts/check.sh

# Build and verify a universal release-configuration app.
Scripts/build.sh
Scripts/verify-bundle.sh
```

For a faster Apple Silicon development build:

```sh
ARCHS=arm64 CONFIGURATION=debug Scripts/build.sh
```

Use `ARCHS=x86_64` for an Intel-only build. The bundle verifier expects the default universal build. Builds are staged separately before replacing the previous output.

| Location | Purpose |
| :--- | :--- |
| [Sources/Glance](Sources/Glance) | App lifecycle, menus, window controller, and image canvas |
| [Sources/GlanceCore](Sources/GlanceCore) | Folder navigation, decoding, caching, file monitoring, and zoom geometry |
| [Tests](Tests) | Regression checks and independently encoded image fixtures |
| [Resources](Resources) | Bundle metadata and privacy manifest |
| [Scripts](Scripts) | Build, verification, icon generation, and release tooling |

The regression suite covers navigation, decoding, cache invalidation, file changes, zoom behavior, and window rendering. It runs without XCTest or a full Xcode installation. [VALIDATION.md](VALIDATION.md) records completed checks and remaining release-testing gaps, including physical Intel hardware, supported macOS versions, and additional camera RAW variants.

Fixture regeneration is optional and uses [Scripts/make-fixtures.py](Scripts/make-fixtures.py) with Pillow 12.3 and WebP/AVIF support. Python and Pillow are not required to build or run Glance.

### Release builds

Public distribution requires an Apple Developer account, a **Developer ID Application** signing identity in Keychain, and a `notarytool` Keychain profile. Set `SIGNING_IDENTITY` to the installed identity and `NOTARY_PROFILE` to the profile name, then run:

```sh
Scripts/release.sh
```

The script runs the checks, builds both architectures, signs the app with the hardened runtime, submits it to Apple for notarization, staples the ticket, and verifies Gatekeeper acceptance. It stops on failure and produces `dist/Glance-1.0.0-macOS.zip` with a SHA-256 checksum. Credentials remain outside the repository.

## Feedback and contributions

[Report a bug or suggest a feature](https://github.com/lklacar/glance/issues). For image or rendering issues, include your macOS version, Mac architecture, file format, and steps to reproduce. Attach a sample only if you are comfortable sharing it.

For code changes, keep the scope focused and run `Scripts/check.sh` before submitting a pull request. Describe the behavior you changed and how you verified it.

## License

Glance is licensed under the [MIT License](LICENSE).

Copyright © 2026 [Luka Klacar](https://github.com/lklacar). Copies or substantial portions of the software must retain this copyright notice and the MIT license notice, including when modified or redistributed commercially. The license is also included in the app bundle.
