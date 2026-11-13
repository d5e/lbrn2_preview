# LightBurn Quick Look for macOS Catalina and Monterey

A small legacy Quick Look generator for macOS Catalina and Monterey. It reads the PNG embedded in a LightBurn `.lbrn` or `.lbrn2` project and gives that image to Finder for file thumbnails and Quick Look previews.

LightBurn stores its project as XML and places the preview PNG in the `Source` attribute of a top-level `Thumbnail` element. This generator extracts that image; it does not render the project geometry.

Thumbnails return the PNG directly to Image I/O. Full previews draw that same raster image into an in-memory, one-page PDF and return `kUTTypePDF`. On the Catalina reference machine, returning encoded image data or a bitmap context caused QuickLookUIService to report `CGImageCreate: invalid image size: 0 x 0` and show the application icon. Supplying image dimensions did not resolve it. The PDF representation bypasses that failing image display path. It does not add image detail or write a PDF beside the project.

## Requirements and compatibility

- macOS 10.15 Catalina or macOS 12 Monterey
- An Intel Mac for the current build
- Apple Command Line Tools with `clang`

The generator uses the same implementation on both systems. Its deployment target and bundle minimum remain macOS 10.15, preserving Catalina compatibility. The build uses the Catalina SDK when it is installed and otherwise uses the current macOS SDK. It has been visually verified on the Catalina reference system and on Monterey 12.7.5 with an Intel Mac.

## Install on this Mac

From the project directory, run:

```sh
./scripts/install.sh
```

The script builds the `.qlgenerator` bundle, installs it in `~/Library/QuickLook`, registers its file type, and refreshes Quick Look's generator and thumbnail caches. It does not need administrator access.

In Finder, select a LightBurn project and press Space to open its Quick Look preview. To use Finder's preview pane, choose **View → Show Preview**. Finder icon thumbnails use the same embedded image.

## Build

```sh
./scripts/build.sh
```

The resulting bundle is `build/LightBurnPreview.qlgenerator`.

## Uninstall

```sh
./scripts/uninstall.sh
```

This removes this generator from `~/Library/QuickLook` and refreshes Quick Look. It leaves project files untouched.

## Limits and safety

- The plugin accepts only the `LightBurnProject` XML root and its direct `Thumbnail` child.
- Input files are limited to 256 MiB; extracted PNGs are limited to 32 MiB and 16 megapixels.
- XML network access and DTDs are not used. Invalid or missing thumbnails produce no preview.
- The embedded image is typically 256 × 256 pixels, so Finder cannot show detail beyond LightBurn's stored thumbnail resolution.

## Troubleshooting

Check that macOS has loaded the generator:

```sh
qlmanage -m plugins | grep -i lightburn
```

If Finder keeps showing a cached generic icon, run:

```sh
qlmanage -r
qlmanage -r cache
```

Then reopen the Finder window. For diagnosis, `qlmanage -t -o /tmp /path/to/file.lbrn2` requests a thumbnail.

## Visual acceptance check

Acceptance requires the embedded design to appear in Finder's Preview pane and Quick Look, as well as the file thumbnail. This was visually confirmed on the Catalina reference machine after the PDF preview change. On Monterey 12.7.5, both the generated thumbnail and the full Quick Look preview were visually confirmed with a user-supplied `.lbrn2` project.

`qlmanage -p -o` only saves generated preview data; its success message does not establish that Finder can display the result. The diagnostic below uses Apple's actual `QLPreviewView` and captures its rendered window for inspection:

```sh
mkdir -p build
xcrun clang -fobjc-arc -framework Cocoa -framework Quartz tools/preview-check.m -o build/preview-check
build/preview-check /absolute/path/to/project.lbrn2 /tmp/lightburn-preview-check.png
```

Inspect the screenshot for the design rather than the LightBurn icon. The diagnostic opens a temporary window for five seconds and then closes it.
