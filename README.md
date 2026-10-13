# PowerVR Rogue black screen repro

Minimal Flutter web app for a regression we saw after upgrading from Flutter 3.41.7 to 3.47.5. On ChromeOS devices with a PowerVR Rogue GPU, the **whole screen** goes black, not just the browser tab.

The app shows full-screen 3840×1980 PNG backgrounds with `Image.memory` (default `FilterQuality.medium`). They are downscaled to the screen size and change every second, like an app moving between pages with large backgrounds.

## Suspected cause

- **Since 3.47, every downscaled image gets a mipmapped texture.** CanvasKit's `drawImageRect` now uses `kFast_SrcRectConstraint` instead of `kStrict_SrcRectConstraint` (Skia `dae8778ca4`, rolled in Flutter 3.47). With the strict constraint, Skia ignored the mipmap mode. Now every `FilterQuality.medium` image drawn smaller than its size gets a GPU-generated mipmapped copy of its texture. For a 3840×1980 image that is about 39 MB, briefly about 68 MB.
- **On PowerVR Rogue, that extra memory seems to cause WebGL context losses.** On ChromeOS, Chrome handles a context loss on these GPUs by restarting the GPU process (`exit_on_context_lost`). That process also draws the system UI, so the whole screen goes black.

## Live demo

https://bvg-gynzy.github.io/flutter_powervr_mipmap_repro/ links all four variants below.

## Build and run

`build.sh` builds the app with both Flutter versions. It expects them as asdf installs in `~/.asdf/installs/flutter/<version>`; edit the path if yours differ.

```sh
./build.sh
python3 -m http.server 8080 --directory build/site
```

Open `http://<host>:8080/` on the device. The index links all four variants:

| Variant | URL | Result on PowerVR Rogue (Asus C202XA) |
|---|---|---|
| 3.41.7 | `/3.41.7/` | works |
| 3.47.5 | `/3.47.5/` | screen flashes black, app crashes |
| 3.47.5, mipmaps disabled | `/3.47.5/?noMipmaps=1` | works |
| 3.41.7, mipmaps disabled | `/3.41.7/?noMipmaps=1` | works (control) |

`?noMipmaps=1` makes `web/flutter_bootstrap.js` patch `CanvasKit.Canvas.prototype.drawImageRectOptions` to always pass `MipmapMode.None`.

The panel in the bottom-left corner shows:
- the Flutter version and the WebGL renderer;
- whether the patch is active;
- controls for `FilterQuality`, the number of stacked images and cycling.

Switching to `none` or `low` turns mipmaps off without the patch. `Stacked images` draws several backgrounds on top of each other to add memory pressure.

The device must reach the host, for example over the same network, or upload `build/site` to any static host.

## Draft issue for flutter/flutter

**Title:** [web] CanvasKit: downscaled images now generate mipmaps (kFast_SrcRectConstraint), blacking out ChromeOS on PowerVR Rogue GPUs

**Steps to reproduce**

1. Open https://bvg-gynzy.github.io/flutter_powervr_mipmap_repro/3.47.5/ (the app first generates six 3840×1980 PNG backgrounds, so it takes a while to load, longer on a slow Chromebook), or build https://github.com/BvG-Gynzy/flutter_powervr_mipmap_repro with Flutter 3.47.5 (`flutter build web`, or `./build.sh` for all variants).
2. Open it in Chrome on a ChromeOS device with a PowerVR Rogue GPU (we used an Asus C202XA, PowerVR Rogue GX6250).
3. Leave it running while it cycles through its 3840×1980 backgrounds.

**Expected results**

The app keeps rendering, as it does with Flutter 3.41.7.

**Actual results**

The whole ChromeOS screen, including the system UI, flashes black and the app crashes.

- The same app built with 3.41.7 works.
- With 3.47.5 it also works when `drawImageRectOptions` is patched to pass `MipmapMode.None` (`?noMipmaps=1`).

**Analysis**

- In 3.41, `CkCanvas.drawImageRect` was drawn with `kStrict_SrcRectConstraint`, which made Skia ignore the mipmap mode.
- #186569 asked to fix blurry downscaled images. #186914 (@harryterkelsen) removed the iterative downscaling workaround in favour of using mipmaps. For CanvasKit, that relies on the Skia change for https://issues.skia.org/issues/500117356, rolled in with Skia `dae8778ca40d` (#186949). CanvasKit now draws with `kFast_SrcRectConstraint`.
- `toSkMipmapMode(FilterQuality.medium)` returns `MipmapMode.Linear`, and that now takes effect. So the default `Image` quality makes the GPU generate a mipmapped copy of the texture for every downscaled image. For a 3840×1980 image that is about 39 MB, briefly about 68 MB.
- On these GPUs the extra GPU memory seems to cause WebGL context losses. ChromeOS handles them by restarting the GPU process (`exit_on_context_lost`). That process also draws the system UI, so the whole screen goes black, and the app cannot recover the way it does from an ordinary context loss.
- The better downscaling is a good change, but it silently increases GPU memory for every Flutter web app that shows large images. Could there be a way to opt out on web, for example a `FilterQuality.medium` that does not use mipmaps, or an engine configuration flag? Today the only workaround we found is patching `CanvasKit.Canvas.prototype.drawImageRectOptions` in `flutter_bootstrap.js`, as this repro does with `?noMipmaps=1`.

**Device and versions**

- Device: Asus C202XA, PowerVR Rogue GX6250, 1366×768
- ChromeOS 16503.95.0, Chrome 144.0.7559.262
- WebGL renderer: `ANGLE (Imagination Technologies, PowerVR Rogue GX6250, OpenGL ES 3.2)`
- Flutter 3.47.5 (bad) vs 3.41.7 (good), CanvasKit renderer
