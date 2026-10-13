{{flutter_js}}
{{flutter_build_config}}

/**
 * With `?noMipmaps=1`, patches CanvasKit so `drawImageRectOptions` always
 * uses `MipmapMode.None`. Images are then sampled as in Flutter 3.41, which
 * drew them with `kStrict_SrcRectConstraint`, under which Skia ignores the
 * mipmap mode.
 */
async function maybeDisableMipmaps() {
  if (new URLSearchParams(window.location.search).get("noMipmaps") !== "1") {
    return;
  }
  const canvasKit = await window.flutterCanvasKitLoaded;
  const drawImageRectOptions = canvasKit.Canvas.prototype.drawImageRectOptions;
  canvasKit.Canvas.prototype.drawImageRectOptions = function (image, src, dst, filterMode, mipmapMode, paint) {
    return drawImageRectOptions.call(this, image, src, dst, filterMode, canvasKit.MipmapMode.None, paint);
  };
  window.__repro_mipmaps_disabled = true;
}

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      await maybeDisableMipmaps();
    } catch (e) {
      console.warn("Could not patch CanvasKit:", e);
    }
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
  },
});
