# LightBurn Quick Look for macOS

LightBurn Quick Look for macOS adds Finder thumbnails and Quick Look previews for `.lbrn` and `.lbrn2` projects when the installed LightBurn version lacks native macOS previews. It is especially useful on Catalina: [LightBurn 1.7.08](https://docs.lightburnsoftware.com/2.2/GetStarted/InstallLightBurn/) is the final release compatible with macOS versions earlier than 11, and this project has been verified with that version on Catalina. Compatibility with other LightBurn releases has not been established across the full version range.

LightBurn stores its projects as XML and places the preview image in the `Source` attribute of a top-level `Thumbnail` element. This generator extracts that embedded image; it does not render the project geometry.

For Finder thumbnails, the generator returns the embedded PNG directly to Image I/O. For full Quick Look previews, it draws the same raster image into a one-page PDF held in memory and returns `kUTTypePDF`. On the Catalina reference Mac, returning encoded image data or a bitmap context caused QuickLookUIService to report `CGImageCreate: invalid image size: 0 x 0` and show the application icon. Supplying image dimensions did not fix the problem, while the PDF representation bypassed the failing display path. The PDF adds no image detail and is not written beside the LightBurn project.

## Requirements and compatibility

- macOS 10.15 or later is the current deployment target.
- The current build targets Intel Macs.
- Apple Command Line Tools with `clang` are required to build.

Compatibility has been visually confirmed on macOS Catalina 10.15 and macOS Monterey 12.7.5, using Intel Macs. The Catalina verification used LightBurn 1.7.08. These are the systems tested so far, not the intended limit of the project. Broader macOS compatibility is a near-term goal, and additional versions and hardware configurations still need confirmation.

The generator uses the same implementation on both verified systems. Its deployment target and bundle minimum remain macOS 10.15 to preserve Catalina compatibility. The build uses the Catalina SDK when installed and otherwise uses the current macOS SDK.

## Install

From the project directory, run:

```sh
./scripts/install.sh
```

The script builds the `.qlgenerator` bundle, installs it in `~/Library/QuickLook`, registers its file type, and refreshes Quick Look's generator and thumbnail caches. It does not require administrator access.

In Finder, select a LightBurn project and press Space to open its Quick Look preview. To show Finder's preview pane, choose **View → Show Preview**. Finder icon thumbnails use the same embedded image.

## Build

```sh
./scripts/build.sh
```

The resulting bundle is `build/LightBurnPreview.qlgenerator`.

## Uninstall

```sh
./scripts/uninstall.sh
```

This removes the generator from `~/Library/QuickLook` and refreshes Quick Look. It leaves LightBurn project files untouched.

## Limits and safety

- The plugin accepts only the `LightBurnProject` XML root and its direct `Thumbnail` child.
- Input files are limited to 256 MiB; extracted PNGs are limited to 32 MiB and 16 megapixels.
- XML network access and DTDs are disabled. Invalid or missing thumbnails produce no preview.
- Embedded images are typically 256 × 256 pixels, so previews cannot show detail beyond LightBurn's stored thumbnail resolution.

## Troubleshooting

Check whether macOS has loaded the generator:

```sh
qlmanage -m plugins | grep -i lightburn
```

If Finder continues to show a cached generic icon, refresh Quick Look's generator and thumbnail caches:

```sh
qlmanage -r
qlmanage -r cache
```

Then reopen the Finder window. To request a thumbnail for diagnosis, run:

```sh
qlmanage -t -o /tmp /path/to/file.lbrn2
```

## Visual verification

The acceptance check confirms that the embedded design appears in Finder's Preview pane and Quick Look, and as the file thumbnail. This has been visually verified on the Catalina reference Mac running LightBurn 1.7.08 after the PDF preview change. On Monterey 12.7.5, both the generated thumbnail and full Quick Look preview were visually checked using a user-supplied `.lbrn2` project.

The repository includes a LightBurn sample at `tests/fixtures/2023-girl-engraving-calibration-alpha.lbrn2`. Run `./scripts/test-sample.sh` to rebuild and install the generator, create its Finder thumbnail, and capture a full Quick Look preview. Inspect both images in `build/sample-test/` to confirm they show the design.

`qlmanage -p -o` only saves generated preview data; a success message does not prove that Finder can display it. The diagnostic below uses Apple's actual `QLPreviewView` and captures its rendered window for inspection:

```sh
mkdir -p build
xcrun clang -fobjc-arc -framework Cocoa -framework Quartz tools/preview-check.m -o build/preview-check
build/preview-check /absolute/path/to/project.lbrn2 /tmp/lightburn-preview-check.png
```

Inspect the screenshot to confirm it shows the design rather than the LightBurn icon. The diagnostic opens a temporary window for five seconds, then closes it.
