# LightBurn Quick Look for macOS

A small legacy Quick Look generator for macOS Catalina. It reads the PNG embedded in a LightBurn `.lbrn` or `.lbrn2` project and gives that image to Finder for file thumbnails and Quick Look previews.

LightBurn stores its project as XML and places the preview PNG in the `Source` attribute of a top-level `Thumbnail` element. This generator extracts that image; it does not render the project geometry.

## Requirements

- macOS 10.15 Catalina (later macOS versions have not been validated)
- An Intel Mac for the current build (Catalina itself only supports Intel)
- Apple Command Line Tools with `clang`

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

Check that Catalina has loaded the generator:

```sh
qlmanage -m plugins | grep -i lightburn
```

If Finder keeps showing a cached generic icon, run:

```sh
qlmanage -r
qlmanage -r cache
```

Then reopen the Finder window. For diagnosis, `qlmanage -t -o /tmp /path/to/file.lbrn2` requests a thumbnail.
