// asaot.ui.DesktopEnv -- the Env every target this library can build TODAY
// actually has: a window with a mouse, no notch, no soft keyboard (MOBILE.md 6.3
// "桌面实现").
//
// WHAT IT MAY HONESTLY READ, AND WHAT IT MAY NOT
// ----------------------------------------------
// Three of the nine values are real here, and the other six are DEFAULTS that no
// backend in this runtime can currently contradict:
//
//   * `locale`      -> Capabilities.language. Real, and the same string AIR
//                      answers with (as_cap_language).
//   * `appState`    -> "active". A desktop window that is not frontmost is still
//                      running; AIR's Stage ACTIVATE/DEACTIVATE events are what a
//                      future E7 turns into "inactive".
//   * `hasHover`    -> true. Every target built today takes a mouse, and the
//                      library's 103 hover branches are written for exactly that.
//   * `hasTouch`    -> FALSE, and NOT because something said so:
//                      Capabilities.touchscreenType is the hardcoded string
//                      "none" in this runtime (emit.ts), so it cannot be consulted
//                      for the truth. A touch-capable build must say so itself.
//   * `pixelRatio`  -> the constructor argument. There is NO device-pixel-ratio
//                      truth reachable from AS3: Capabilities.screenDPI is a
//                      hardcoded 96 (Windows) / 72 (elsewhere) constant, and the
//                      window backend's own scale factor is a C-side global that
//                      AS3 cannot see. Guessing from screenDPI would be a
//                      fabricated number; `check-dpi` instead proves the rendering
//                      honours whatever the platform asked for. Defaults to 1.
//   * `safeArea`    -> all zeros. A desktop window does not overlay a status bar.
//   * `keyboardRect`-> zero-size until something sets it (no soft keyboard).
//   * `reduceMotion`-> false, `isDark` -> false: both are SYSTEM preferences this
//                      runtime does not expose yet (MOBILE.md E5/E8). A build that
//                      knows them sets them on this object.
//
// So: this class is the honest floor, not a stand-in that pretends to measure. A
// phone shell constructs it (or an EnvBase) and SETS the values it knows, which is
// why the writers live on EnvBase rather than being private here.
package asaot.ui
{
    import flash.system.Capabilities;

    public class DesktopEnv extends EnvBase
    {
        public function DesktopEnv(pixelRatio:Number = 1)
        {
            super();
            this._pixelRatio = pixelRatio;
            this._locale = Capabilities.language;
        }
    }
}
