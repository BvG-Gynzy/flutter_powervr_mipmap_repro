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

/**
 * Wraps WebGL's `generateMipmap` to count calls in
 * `window.__repro_generate_mipmap_calls`, and with `?mipGeneration=` changes
 * what it does (requested in flutter/flutter#194283):
 * - `skip`: does nothing, so textures keep their mipmapped allocation but no
 *   mips are generated.
 * - `finish`: calls `gl.finish()` first, so pending GPU work completes before
 *   the mips are generated.
 */
function wrapGenerateMipmap() {
  const mode = new URLSearchParams(window.location.search).get("mipGeneration");
  window.__repro_mip_generation = mode === "skip" || mode === "finish" ? mode : "default";
  window.__repro_generate_mipmap_calls = 0;
  for (const context of [window.WebGLRenderingContext, window.WebGL2RenderingContext]) {
    if (!context) {
      continue;
    }
    const generateMipmap = context.prototype.generateMipmap;
    context.prototype.generateMipmap = function (target) {
      window.__repro_generate_mipmap_calls++;
      run.generateMipmapCalls++;
      saveRun();
      if (mode === "skip") {
        return;
      }
      if (mode === "finish") {
        this.finish();
      }
      return generateMipmap.call(this, target);
    };
    const texStorage2D = context.prototype.texStorage2D;
    if (texStorage2D) {
      context.prototype.texStorage2D = function (target, levels, internalFormat, width, height) {
        if (levels > 1) {
          run.mipmappedAllocations.push(`${width}x${height}, ${levels} levels`);
          saveRun();
        }
        return texStorage2D.apply(this, arguments);
      };
    }
  }
}

/**
 * Records this page load in `localStorage` as it goes, so the numbers survive
 * the GPU process restart that blacks out the screen. The previous page load's
 * record is published as `window.__repro_previous_run` (JSON) for the panel.
 */
const runStorageKey = "repro_run";
const run = {
  url: window.location.pathname + window.location.search,
  startedAt: new Date().toISOString(),
  stage: "loading",
  generateMipmapCalls: 0,
  mipmappedAllocations: [],
};

function saveRun() {
  try {
    localStorage.setItem(runStorageKey, JSON.stringify(run));
  } catch (e) {
    // Storage unavailable: the panel then has no previous run to show.
  }
}

function startRun() {
  try {
    window.__repro_previous_run = localStorage.getItem(runStorageKey);
  } catch (e) {
    window.__repro_previous_run = null;
  }
  saveRun();
}

/** Called by the app to record how far it got. */
window.__repro_set_stage = function (stage) {
  run.stage = stage;
  saveRun();
};

startRun();
wrapGenerateMipmap();

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
