// hymn/HymnView.as -- the whole hymn app's window, as one describe() pass.
//
// WHAT THIS FILE IS: a port of the Rust app's `src/ui/{titlebar,library,reader,player,
// splash}.rs` into asaot.ui nodes. The palette and the METRICS live in HymnTheme;
// this file contains the ARRANGEMENT, the behaviour a click causes, and the two
// measurements a declarative tree cannot express on its own:
//
//   * PILL GEOMETRY. A label inside a row cannot be shrink-wrapped reliably (measured:
//     a 45pt advance solving into a 45pt box with a 45x2 zero-height label). Every
//     pill, badge and segment is therefore built by `plate()`, which asks the same
//     TextField the painter uses for the advance and computes padX + advance + padX.
//   * DOCUMENT HEIGHT. The reader is a scroll view, so its content column must have a
//     definite height BEFORE layout solves: lyrics are wrapped by hand (HymnWrap) and
//     every row is given an explicit height, with the total handed to the column.
//
// THE PLAYER IS SILENT, AND THE UI SAYS SO. Upstream synthesises every tune through
// rustysynth; this port has the tune metadata but no synthesiser yet (see
// hymn/README.md), so the transport drives a real clock over the real section map and
// marks the window "SILENT" where the instrument would be. Nothing pretends to sound.
package hymn
{
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.UiApp;
    import asaot.ui.View;
    import asaot.ui.box;
    import asaot.ui.column;
    import asaot.ui.icon;
    import asaot.ui.row;
    import asaot.ui.scrollView;
    import asaot.ui.style.Length;
    import asaot.ui.style.StyleRefinement;
    import asaot.ui.text;
    import asaot.ui.textField;
    import asaot.ui.virtualList;

    import flash.display.DisplayObject;

    public class HymnView extends View
    {
        public var model:HymnModel;
        public var app:UiApp;

        // ONE FACE PER ROLE, as upstream (Noto Sans / Noto Serif / Noto Sans Mono).
        // These are the Windows families with the same role: a UI face, a reading face
        // with a real italic-capable serif, and a fixed-pitch face for numbers and tags.
        public static const SANS:String = "Segoe UI";
        public static const SERIF:String = "Georgia";
        public static const MONO:String = "Consolas";

        // ---- icon paths (24x24, stroke unless noted) ---------------------
        private static const I_SEARCH:String = "M11 4 A7 7 0 1 0 11 18 A7 7 0 1 0 11 4 M16.2 16.2 L21 21";
        private static const I_GEAR:String = "M12 9 A3 3 0 1 0 12 15 A3 3 0 1 0 12 9"
            + " M12 2.5 V5 M12 19 V21.5 M2.5 12 H5 M19 12 H21.5"
            + " M5.2 5.2 L7 7 M17 17 L18.8 18.8 M18.8 5.2 L17 7 M7 17 L5.2 18.8";
        private static const I_MIN:String = "M6 12 H18";
        private static const I_MAX:String = "M6.5 6.5 H17.5 V17.5 H6.5 Z";
        private static const I_CLOSE:String = "M6.5 6.5 L17.5 17.5 M17.5 6.5 L6.5 17.5";
        private static const I_PLAY:String = "M8.5 5 L19 12 L8.5 19 Z";
        private static const I_PAUSE:String = "M8 5 H11 V19 H8 Z M15.5 5 H18.5 V19 H15.5 Z";
        private static const I_CHEV:String = "M14 6 L8 12 L14 18";
        // U+2212 MINUS SIGN, not a hyphen: the pair reads as an operation, and a hyphen
        // at this size sits high and looks like a dash.
        private static const MINUS:String = "−";
        private static const VOICE_SEP:String = " · ";

        private static const I_LIB:String = "M4 5 H9 V19 H4 Z M11 5 H16 V19 H11 Z M18 5 H20 V19 H18 Z";

        // Caches. A describe pass runs on every frame of an animation (the splash alone
        // is ~2s of them), so a style object per node per frame is not affordable:
        //   texts  -- one StyleRefinement per (family, size, bold, colour, w, h, align)
        //   plates -- the [boxStyle, textStyle] pair per pill geometry
        //   lyric  -- the one style every lyric row shares
        private var texts:Object;
        private var plates:Object;
        private var lyric:StyleRefinement;
        private var lyricKey:String = "";

        // ---- root -------------------------------------------------------
        override public function render():Node
        {
            var t:HymnTheme = model.theme;
            var band:Array = [this.sidebar(t), this.reader(t)];
            var kids:Array = [
                this.titlebar(t),
                row({ key: "band", style: t.BAND, ariaName: "" }, band),
                this.player(t)
            ];
            // The splash is the LAST child, absolutely positioned: it covers the window
            // it hides, and it is described from the same tick as everything else.
            if (model.splash != 2) kids.push(this.splash(t));
            return column({ key: "root", style: t.ROOT, ariaName: "Hymn Book" }, kids);
        }

        // ---- titlebar ---------------------------------------------------
        //
        // Client-side decoration: the descriptor asks AI for systemChrome=none, so this
        // bar IS the window frame. Pressing it and dragging calls
        // NativeWindow.startMove() from HymnMain -- see the note there for why the app
        // must not run a move loop of its own.
        private function titlebar(t:HymnTheme):Node
        {
            var self:HymnView = this;
            var controls:Array = [
                this.iconBtn(t, "theme", I_GEAR, 16, t.text2, t.bg, t.raised,
                    function (e:Object):void { self.model.toggleTheme(); }, "Toggle theme"),
                this.fixed(8, 8),
                this.iconBtn(t, "min", I_MIN, 16, t.text2, t.bg, t.raised,
                    function (e:Object):void { self.winDo("minimize"); }, "Minimize"),
                this.iconBtn(t, "max", I_MAX, 14, t.text2, t.bg, t.raised,
                    function (e:Object):void { self.winDo("maximize"); }, "Maximize"),
                this.iconBtn(t, "close", I_CLOSE, 14, t.text2, t.bg, t.raised,
                    function (e:Object):void { self.winDo("close"); }, "Close")
            ];
            var brand:Array = [
                this.logo(30),
                column({ key: "brandText", style: t.BRAND_COL }, [
                    text("Hymn Book", { key: "brandName",
                        style: this.txt(SANS, 14, true, t.text, 130, 19, "left"),
                        ariaName: "Hymn Book" }),
                    text("Faith Tabernacle", { key: "brandSub",
                        style: this.txt(SANS, 11, false, t.text3, 130, 15, "left"),
                        ariaName: "Faith Tabernacle" })
                ])
            ];
            return row({ key: "titlebar", style: t.TB, ariaName: "Title bar" }, [
                row({ key: "brand", style: t.BRAND_ROW }, brand),
                row({ key: "winbtns", style: t.CTRL_ROW, ariaName: "Window controls" }, controls)
            ]);
        }

        // The mark from `assets/icon/icon.svg`: an "F" and a note, on a 512 grid, inside
        // a rounded gold tile. Drawn from five rectangles so it scales to any size
        // without an image asset.
        private function logo(size:Number):Node
        {
            var t:HymnTheme = model.theme;
            var k:Number = size / 512;
            var shape:Array = [];
            var rects:Array = [
                [150, 112, 62, 288, 31],    // stem
                [150, 112, 212, 62, 31],    // top bar
                [150, 222, 150, 56, 28],    // middle bar
                [286, 314, 88, 88, 44],     // note head
                [356, 232, 18, 126, 9]      // note stem
            ];
            for (var i:int = 0; i < rects.length; i++)
            {
                var r:Array = rects[i];
                shape.push(box({ key: "s" + String(i), style: this.abs(
                    Math.round(r[0] * k), Math.round(r[1] * k),
                    Math.round(r[2] * k), Math.round(r[3] * k),
                    Math.round(r[4] * k), t.ink) }));
            }
            return box({ key: "logo", style: this.tile(size, Math.round(112 * k), t.gold),
                         ariaName: "Logo" }, shape);
        }

        private function abs(x:Number, y:Number, w:Number, h:Number, radius:Number, bg:uint):StyleRefinement
        {
            return StyleRefinement.from({
                position: "absolute", inset: [y, null, null, x],
                size: [Length.px(w), Length.px(h)], cornerRadii: radius, background: bg
            });
        }

        // ---- small factories --------------------------------------------
        // 36pt round icon button (src/ui/widgets.rs icon_button).
        private function iconBtn(t:HymnTheme, key:String, path:String, glyph:Number, color:uint,
                                 bg:uint, hover:uint, onClick:Function, aria:String):Node
        {
            return box({ key: key, style: this.tile(36, 999, bg),
                         onClick: onClick, ariaName: aria }, [
                icon(path, { key: key + ":i", size: [Length.px(glyph), Length.px(glyph)],
                             color: color, stroke: true, fill: false, strokeWidth: 1.6 })
            ]);
        }

        private function tile(size:Number, radius:Number, bg:uint):StyleRefinement
        {
            var ck:String = "t|" + String(size) + "|" + String(radius) + "|" + String(bg);
            if (this.texts == null) this.texts = {};
            var s:StyleRefinement = this.texts[ck] as StyleRefinement;
            if (s == null)
            {
                s = StyleRefinement.from({
                    flexDirection: "row", alignItems: "center", justifyContent: "center",
                    size: [Length.px(size), Length.px(size)],
                    cornerRadii: radius, background: bg
                });
                this.texts[ck] = s;
            }
            return s;
        }

        private function fixed(w:Number, h:Number):Node
        {
            var s:StyleRefinement = this.texts == null ? null : this.texts["f|" + String(w) + "|" + String(h)] as StyleRefinement;
            if (s == null)
            {
                if (this.texts == null) this.texts = {};
                s = StyleRefinement.from({ size: [Length.px(w), Length.px(h)] });
                this.texts["f|" + String(w) + "|" + String(h)] = s;
            }
            return box({ key: "gap" + String(w) + "x" + String(h), style: s });
        }

        // A text run with BOTH axes explicit. A null height solves to zero (measured:
        // pills came out 45x2) and a null width inside a row is a flex-basis of zero,
        // so every label in this app states its box.
        private function txt(family:String, size:Number, bold:Boolean, color:uint,
                             w:Number, h:Number, align:String):StyleRefinement
        {
            if (this.texts == null) this.texts = {};
            var ck:String = "x|" + family + "|" + String(size) + "|" + String(bold) + "|" + String(color)
                + "|" + String(w) + "|" + String(h) + "|" + align;
            var s:StyleRefinement = this.texts[ck] as StyleRefinement;
            if (s == null)
            {
                s = StyleRefinement.from({
                    size: [Length.px(w), Length.px(h)],
                    text: { fontFamily: family, fontSize: size,
                            fontWeight: bold ? "bold" : "normal", color: color,
                            textAlign: align, whiteSpace: "nowrap", textOverflow: "clip" }
                });
                this.texts[ck] = s;
            }
            return s;
        }

        // ---- plate(): a measured pill -----------------------------------
        //
        // WHY THE WIDTH IS COMPUTED HERE AND NOT SHRINK-WRAPPED BY THE BOX: a text node
        // inside a ROW is a FLEX item, and a flex item starts from flex-basis:auto with
        // flex-shrink:1 -- its intrinsic advance is not what the row wraps to. Measured
        // on this window before the change: the "All 1000" pill solved 45pt wide around
        // a 45x2 label (never measured at all), for two strings whose advances are 41
        // and 73. HymnWrap.width() IS the painter's advance (a TextField with the same
        // face), so padX + advance + padX is exact -- and it is the same measurement the
        // reader wraps lyrics with, so a pill and the prose beside it agree.
        private function plate(label:String, o:Object):Node
        {
            var t:HymnTheme = model.theme;
            var family:String = o.family == null ? SANS : String(o.family);
            var fs:Number = o.size == null ? 12 : Number(o.size);
            var bold:Boolean = o.bold == true;
            var padX:Number = o.padX == null ? 12 : Number(o.padX);
            var w:Number = o.w == null ? Math.ceil(HymnWrap.width(label, family, fs)) + padX * 2 : Number(o.w);
            var h:Number = o.h == null ? 20 : Number(o.h);
            var radius:Number = o.radius == null ? 6 : Number(o.radius);
            // A STADIUM IS A RADIUS OF h/2, NOT "SOMETHING HUGE". The painter calls
            // Graphics.drawRoundRect(0, 0, w, h, r * 2, r * 2), and Flash clamps the
            // ellipse DIAMETER to the box: r = 999 on a 69x30 pill becomes a 69-wide,
            // 30-tall ellipse -> the top and bottom edges bow and the control reads as an
            // oval. Clamping to h/2 keeps the caps semicircular at any width.
            if (radius > h / 2) radius = h / 2;
            var bg:uint = o.bg == null ? t.raised : uint(o.bg);
            var fg:uint = o.fg == null ? t.text3 : uint(o.fg);
            var borderW:Number = (o.border == null || Number(o.border) == 0) ? 0 : 1;
            var borderC:uint = o.borderColor == null ? t.line : uint(o.borderColor);
            var mt:Number = o.mt == null ? 0 : Number(o.mt);
            var justify:String = o.justify == null ? "center" : String(o.justify);
            if (this.plates == null) this.plates = {};
            var ck:String = t.name + "|" + String(w) + "|" + String(h) + "|" + family + "|" + String(fs)
                + "|" + String(bold) + "|" + String(bg) + "|" + String(fg) + "|" + String(radius)
                + "|" + String(borderW) + "|" + String(borderC) + "|" + String(padX) + "|" + justify
                + "|" + String(mt);
            var pair:Array = this.plates[ck] as Array;
            if (pair == null)
            {
                var boxStyle:StyleRefinement = StyleRefinement.from({
                    flexDirection: "row", alignItems: "center", justifyContent: justify,
                    size: [Length.px(w), Length.px(h)],
                    background: bg, cornerRadii: radius,
                    padding: [0, padX, 0, padX],
                    borderWidths: borderW, borderColor: borderC,
                    margin: [mt, 0, 0, 0]
                });
                // Both axes for the label: a null height solves to zero, and a null width
                // in a row is a flex-basis of zero.
                var lineBox:Number = Math.round(h * 0.9);
                var textStyle:StyleRefinement = StyleRefinement.from({
                    size: [Length.px(w - padX * 2), Length.px(lineBox)],
                    text: { fontFamily: family, fontSize: fs,
                            fontWeight: bold ? "bold" : "normal", color: fg,
                            textAlign: "center", whiteSpace: "nowrap", textOverflow: "clip" }
                });
                pair = [boxStyle, textStyle];
                this.plates[ck] = pair;
            }
            var desc:Object = { key: String(o.key), style: pair[0] };
            if (o.onClick != null) desc.onClick = o.onClick;
            if (o.ariaName != null) desc.ariaName = o.ariaName;
            return box(desc, [text(label, { key: String(o.key) + ":t", style: pair[1] })]);
        }

        // ---- window controls --------------------------------------------
        //
        // The descriptor asks for systemChrome=none, so the OS frame -- and with it the
        // caption buttons and the drag area -- is gone. Both jobs are ours: HymnMain
        // turns a pointer press on the title bar into NativeWindow.startMove() (a real
        // system move, so snapping and a drag past the screen edge keep working), and
        // these buttons call the real NativeWindow methods.
        //
        // WHY NOT A DRAG LOOP OF OUR OWN: a per-frame move fights the compositor and
        // loses the OS snap zones; startMove() hands the gesture to the window manager
        // exactly as a caption drag would. It also returns false on a maximized window,
        // which is AIR's own answer -- nothing to special-case here.
        private function winDo(what:String):void
        {
            var w:Object = this.nativeWindow();
            if (w == null) return;
            if (what == "minimize") w.minimize();
            else if (what == "maximize")
            {
                // Toggle, like the caption button: maximize() on an already maximized
                // window is a no-op in AIR, so the restore branch has to be explicit.
                if (w.displayState == "maximized") w.restore();
                else w.maximize();
            }
            else if (what == "close") w.close();
        }

        private function nativeWindow():Object
        {
            var d:DisplayObject = this.app == null ? null : this.app.rootDisplay();
            if (d == null || d.stage == null) return null;
            return d.stage.nativeWindow;
        }

        // ---- library ----------------------------------------------------
        //
        // The slot is 392 wide (380 + the 12pt gap it vacates) and CLIPS: the pane
        // slides out from under the reader rather than squeezing it, which is the whole
        // reason the animation looks like a drawer and not a reflow.
        private function sidebar(t:HymnTheme):Node
        {
            var slotW:Number = Math.round(model.sideW);
            // A CLOSED drawer is a zero-width slot, not a removed one: keeping the key
            // stable means the library is not torn down and rebuilt on every open.
            if (slotW <= 0)
            {
                return box({ key: "slot", style: StyleRefinement.from({
                    size: [Length.px(0), Length.pct(1)] }) });
            }
            var slotStyle:StyleRefinement = StyleRefinement.from({
                flexDirection: "row", size: [Length.px(slotW), Length.pct(1)],
                overflow: "hidden", padding: [0, HymnTheme.GAP, 0, 0]
            });
            return box({ key: "slot", style: slotStyle }, [this.library(t)]);
        }

        private function library(t:HymnTheme):Node
        {
            var self:HymnView = this;
            var total:int = model.hymns.length;
            var tuned:int = model.tunedCount();
            var count:String = model.ready
                ? (String(model.visible.length) + " of " + String(total))
                : "loading";
            var allOn:Boolean = model.filter == HymnModel.ALL_ROWS;
            var tunedOn:Boolean = model.filter == HymnModel.TUNED_ROWS;
            // Two flex_1 segments of a 380-20-20 wide, p(3), gap(4) row: the widths are
            // arithmetic here so neither segment is a percentage child.
            var segW:Number = Math.floor((HymnTheme.LIB_W - 2 - HymnTheme.LIB_PAD * 2
                - HymnTheme.SEG_PAD * 2 - HymnTheme.SEG_GAP) / 2);
            var segs:Array = [
                this.plate("All " + String(total), { key: "segAll", w: segW, h: HymnTheme.SEG_H,
                    radius: 999, bg: allOn ? t.accentSoft : t.raised,
                    fg: allOn ? t.accent : t.text3, bold: true, size: 12.5,
                    onClick: function (e:Object):void { self.model.setFilter(HymnModel.ALL_ROWS); },
                    ariaName: "All hymns" }),
                this.plate("With tune " + String(tuned), { key: "segTuned", w: segW, h: HymnTheme.SEG_H,
                    radius: 999, bg: tunedOn ? t.accentSoft : t.raised,
                    fg: tunedOn ? t.accent : t.text3, bold: true, size: 12.5,
                    onClick: function (e:Object):void { self.model.setFilter(HymnModel.TUNED_ROWS); },
                    ariaName: "Hymns with a tune" })
            ];
            var titleRow:Array = [
                text("Library", { key: "libTitle",
                    style: this.txt(SANS, 22, true, t.text, 150, 30, "left"), ariaName: "Library" }),
                row({ key: "libCountWrap", style: t.LIB_COUNT_ROW }, [
                    text(count, { key: "libCount",
                        style: this.txt(SANS, 12, false, t.text3,
                            Math.ceil(HymnWrap.width(count, SANS, 12)) + 4, 16, "left") }),
                    this.iconBtn(t, "collapse", I_CHEV, 16, t.text3, t.panel, t.raised,
                        function (e:Object):void { self.model.toggleSidebar(); }, "Collapse library")
                ])
            ];
            var body:Array = [];
            if (model.ready && model.visible.length == 0)
            {
                body.push(text("No hymn matches that search.", { key: "none",
                    style: this.txt(SANS, 13, false, t.text3, HymnTheme.LIB_W - 40, 20, "left") }));
            }
            else
            {
                body.push(this.list(t));
            }
            return column({ key: "library", style: t.LIB, ariaName: "Library" }, [
                column({ key: "libHead", style: t.LIB_HEAD }, [
                    row({ key: "libTitleRow", style: t.LIB_TITLE_ROW }, titleRow),
                    row({ key: "search", style: t.SEARCH, ariaName: "Search" }, [
                        icon(I_SEARCH, { key: "searchIcon", size: [Length.px(16), Length.px(16)],
                                         color: t.text3, stroke: true, fill: false, strokeWidth: 1.7 }),
                        textField({ key: "searchField", style: t.SEARCH_TEXT,
                                    value: model.query,
                                    placeholder: "Search number, title or words",
                                    onChange: function (v:String):void { self.model.setQuery(v); },
                                    ariaName: "Search number, title or words" })
                    ]),
                    row({ key: "filters", style: t.FILTERS }, segs)
                ]),
                column({ key: "libList", style: t.LIST }, body)
            ]);
        }

        private function list(t:HymnTheme):Node
        {
            var self:HymnView = this;
            return virtualList({
                key: "rows",
                style: t.LIST,
                rowHeight: HymnTheme.ROW_H,
                count: model.visible.length,
                offsetY: model.libOffset,
                overscan: 2,
                onScroll: function (y:Number):void { self.model.setLibOffset(y); },
                renderRow: function (i:int):Node { return self.rowAt(t, i); }
            });
        }

        private function rowAt(t:HymnTheme, i:int):Node
        {
            var self:HymnView = this;
            if (i < 0 || i >= model.visible.length) return box({ key: "r" + String(i), style: t.ROW });
            var hymnIndex:int = model.visible[i];
            var h:Object = model.hymns[hymnIndex];
            var on:Boolean = hymnIndex == model.sel;
            var tune:Object = model.tuneOf(h);
            // The number tile: 42pt, mono, bold -- the library's left rail.
            var tileNode:Node = this.plate(String(h.number), {
                key: "n" + String(i), family: MONO, size: 13, bold: true, padX: 0,
                w: HymnTheme.TILE, h: HymnTheme.TILE, radius: HymnTheme.TILE_R,
                bg: on ? t.accent : t.raised, fg: on ? t.onAccent : t.text2 });
            // The tune badge takes 40pt of the row when it is there, so the two text
            // runs are fitted to what is left -- and FITTED, not merely clipped: a
            // subtitle that runs through the panel edge reads as a defect.
            var textW:Number = HymnTheme.LIB_W - 42 - HymnTheme.TILE - 14 - 16
                - (tune != null ? 46 : 0) - 12;
            var col:Array = [
                text(HymnWrap.fit(String(h.title), textW, SANS, 14.5, true), { key: "t" + String(i),
                    style: this.txt(SANS, 14.5, true, t.text, textW, 18, "left") }),
                text(HymnWrap.fit(String(h.firstLine), textW, SANS, 12.5), { key: "s" + String(i),
                    style: this.txt(SANS, 12.5, false, on ? t.text2 : t.text3, textW, 16, "left") })
            ];
            var parts:Array = [tileNode, column({ key: "c" + String(i), style: t.ROW_COL }, col)];
            if (tune != null)
            {
                // The tune badge is upstream's "$length s" chip in the accent tone: this
                // hymn HAS a melody, and the badge is how the list says so without a
                // second column of text.
                parts.push(this.plate(String(Math.round(tune.length)) + "s", {
                    key: "b" + String(i), family: MONO, size: 9.5, bold: true, padX: 8,
                    h: 20, radius: 999, bg: t.accentSoft, fg: t.accent, ariaName: "Tune length" }));
            }
            return box({ key: "r" + String(i), style: t.ROW, ariaName: "Hymn " + String(h.number) }, [
                row({ key: "ri" + String(i),
                      style: on ? t.ROW_IN_ON : t.ROW_IN,
                      onClick: function (e:Object):void { self.model.pick(hymnIndex); },
                      ariaName: String(h.number) + " " + String(h.title) }, parts)
            ]);
        }

        // ---- reader -----------------------------------------------------
        private function reader(t:HymnTheme):Node
        {
            var self:HymnView = this;
            var h:Object = model.current();
            if (h == null)
            {
                return column({ key: "reader", style: t.READER, ariaName: "Reader" }, [
                    row({ key: "rToolbar", style: t.TOOLBAR }, [
                        text("Loading the hymn book...", { key: "rLoading",
                            style: this.txt(SANS, 13, false, t.text3, 300, 18, "left") })
                    ])
                ]);
            }

            // The document's measure comes from the window, not from a constant: the
            // reader takes whatever the sidebar slot leaves, minus the card's two 1pt
            // borders and the 40pt side padding.
            // minus the card's two 1pt borders AND the 8pt lane the "stable" scrollbar
            // gutter reserves: the content box is what is left, and the wrap and the
            // boxes must be that same number or the title is 8pt wider than its own
            // column (measured: title0 782 inside a 774 box).
            var innerW:Number = this.stageW() - HymnTheme.PAD * 2
                - Math.round(model.sideW) - 2 - 8;
            if (innerW < 240) innerW = 240;
            // ONE number for the wrap AND the boxes, capped at the 780pt measure
            // upstream keeps: with the drawer closed the reader is 1200pt wide and a
            // full-width lyric column would run the eye across the whole window. The
            // column is CENTRED inside the card, so the cap costs nothing but margin
            // (measured before the fix: the widened card left 855 physical px of dead
            // space on the right, i.e. the text hugged the left edge).
            var docW:Number = innerW - HymnTheme.CONTENT_PAD * 2;
            if (docW > HymnTheme.CONTENT_MAX) docW = HymnTheme.CONTENT_MAX;

            var size:Number = model.lyricSize;
            var lineH:Number = Math.round(size * HymnTheme.LINE_RATIO);
            // Two measures: a verse line starts after the 48pt gutter and the 12pt rule
            // padding; a chorus line starts inside the card's 22pt inset.
            var verseW:Number = docW - 12 - HymnTheme.GUTTER_W;
            var chorusW:Number = docW - 44;

            var blocks:Array = h.blocks;
            var lays:Array = [];
            var ys:Array = [];
            var contentH:Number = HymnTheme.CONTENT_PAD + this.titleBlockH(h, docW, t);

            for (var i:int = 0; i < blocks.length; i++)
            {
                var lay:Object = this.layoutBlock(blocks[i], verseW, chorusW, size, lineH);
                ys.push(contentH);
                lays.push(lay);
                contentH += lay.h + HymnTheme.BLOCK_PB;
            }
            contentH += 260;    // trailing breathing room, as upstream (a `.h(260)` spacer)

            // Published for the follow animation: which block is sounding, how tall the
            // viewport is, and how far the content can scroll.
            var viewH:Number = this.readerH() - HymnTheme.TOOLBAR_H - 2;
            model.viewH = viewH;
            model.maxScroll = contentH > viewH ? contentH - viewH : 0;
            model.blockY = model.blockIndex < ys.length ? Number(ys[model.blockIndex]) : 0;

            var docKids:Array = [this.titleBlock(h, docW, t)];
            for (var k:int = 0; k < blocks.length; k++)
            {
                docKids.push(this.blockView(t, blocks[k], k, lays[k], lineH, docW));
            }
            if (blocks.length == 0)
            {
                docKids.push(text(String(h.firstLine), { key: "rEmpty",
                    style: this.txt(SERIF, size, false, t.text, docW, lineH, "left") }));
            }
            docKids.push(this.fixed(10, 260));

            // Two boxes on purpose: the SCROLL child fills the card and carries the
            // total height, the MEASURE child is the 780pt column the lyrics were wrapped
            // for. One box cannot do both -- pct(1) children would take the card's width
            // and the wrap (computed from 780) would no longer match what is painted.
            var docStyle:StyleRefinement = StyleRefinement.from({
                flexDirection: "column", alignItems: "center",
                size: [Length.pct(1), Length.px(contentH)],
                padding: [HymnTheme.CONTENT_PAD, 0, 0, 0]
            });
            var measureStyle:StyleRefinement = StyleRefinement.from({
                flexDirection: "column",
                size: [Length.px(docW), Length.px(contentH - HymnTheme.CONTENT_PAD)]
            });

            var scrollY:Number = model.scrollY;
            model.declaredScroll = scrollY;
            return column({ key: "reader", style: t.READER, ariaName: "Hymn " + String(h.number) }, [
                this.toolbar(t, h),
                scrollView({ key: "rScroll", style: t.READ_SCROLL, wheelStep: 40,
                             offsetY: scrollY,
                             scrollbarGutter: "stable",
                             barThickness: 8,
                             scrollbarX: "never",
                             onScroll: function (x:Number, y:Number):void {
                                 self.setScroll(y);
                             },
                             ariaName: "Lyrics" }, [
                    column({ key: "rDoc", style: docStyle }, [
                        column({ key: "rMeasure", style: measureStyle }, docKids)
                    ])
                ])
            ]);
        }

        // The scroll view's onScroll is also fired by THIS app's own declared offset, so
        // an echo is not a gesture: only a value that differs from what we asked for
        // counts as the reader taking over (and stops the follow).
        private function setScroll(y:Number):void
        {
            model.setScrollY(y, model.declaredScroll);
        }

        // Height of the reader card, from the window: total - titlebar - gaps - player.
        private function readerH():Number
        {
            return this.stageH() - HymnTheme.TB_H - HymnTheme.GAP * 2 - HymnTheme.PLAYER_H;
        }

        private function toolbar(t:HymnTheme, h:Object):Node
        {
            var self:HymnView = this;
            var left:Array = [];
            if (!model.sidebarOpen)
            {
                left.push(this.iconBtn(t, "openLib", I_LIB, 16, t.text2, t.raised, t.bg,
                    function (e:Object):void { self.model.toggleSidebar(); }, "Show library"));
            }
            left.push(this.plate("HYMN " + String(h.number), {
                key: "hymnBadge", family: MONO, size: 12, bold: true, padX: 12,
                h: 28, radius: 999, bg: t.accentSoft, fg: t.accent,
                ariaName: "Hymn " + String(h.number) }));
            // A- / A+ live inside one raised track (upstream's segmented control).
            var steps:Array = [
                this.plate("A" + MINUS, { key: "minus", family: SANS, size: 13, bold: true, padX: 0,
                    w: 40, h: 32, radius: 999, bg: t.raised, fg: t.text2,
                    onClick: function (e:Object):void { self.model.setLyricSize(model.lyricSize - 1); },
                    ariaName: "Smaller lyrics" }),
                this.plate("A+", { key: "plus", family: SANS, size: 13, bold: true, padX: 0,
                    w: 40, h: 32, radius: 999, bg: t.raised, fg: t.text2,
                    onClick: function (e:Object):void { self.model.setLyricSize(model.lyricSize + 1); },
                    ariaName: "Larger lyrics" })
            ];
            return row({ key: "rToolbar", style: t.TOOLBAR }, [
                row({ key: "toolLeft", style: t.TOOL_LEFT }, left),
                row({ key: "toolRight", style: t.SEGCTL }, steps)
            ]);
        }

        // The title block: the hymn's name over the chips that describe it.
        private function titleRows(h:Object, docW:Number):Array
        {
            return HymnWrap.lines(String(h.title), docW, SANS, HymnTheme.TITLE_FS, true);
        }

        private function titleBlockH(h:Object, docW:Number, t:HymnTheme):Number
        {
            var rows:int = this.titleRows(h, docW).length;
            if (rows < 1) rows = 1;
            return rows * HymnTheme.TITLE_LH + 14 + HymnTheme.CHIP_H + HymnTheme.TITLE_PB;
        }

        private function titleBlock(h:Object, docW:Number, t:HymnTheme):Node
        {
            var rows:Array = this.titleRows(h, docW);
            var kids:Array = [];
            var hh:Number = HymnTheme.TITLE_LH;
            for (var i:int = 0; i < rows.length; i++)
            {
                kids.push(text(String(rows[i]), { key: "title" + String(i),
                    style: this.txt(SANS, HymnTheme.TITLE_FS, true, t.text, docW, hh, "left") }));
            }
            var chips:Array = [];
            var vc:int = int(h.verseCount);
            chips.push(this.plate(vc == 1 ? "1 verse" : String(vc) + " verses",
                { key: "chipVerses", h: HymnTheme.CHIP_H, padX: 12, radius: 999,
                  bg: t.raised, fg: t.text2, size: 12 }));
            if (h.hasChorus)
            {
                chips.push(this.plate("Chorus", { key: "chipChorus", h: HymnTheme.CHIP_H,
                    padX: 12, radius: 999, bg: t.raised, fg: t.text2, size: 12 }));
            }
            var tune:Object = model.tuneOf(h);
            if (tune != null)
            {
                chips.push(this.plate("Parts: " + String(tune.voices).split(",").join(", "), { key: "chipParts",
                    h: HymnTheme.CHIP_H, padX: 12, radius: 999, bg: t.raised, fg: t.text2, size: 12 }));
            }
            kids.push(row({ key: "chips", style: t.CHIPS }, chips));
            var style:StyleRefinement = StyleRefinement.from({
                flexDirection: "column", size: [Length.pct(1), Length.px(this.titleBlockH(h, docW, t))]
            });
            return column({ key: "titleBlock", style: style }, kids);
        }

        // One block's rows AND its height, in one place: the height the scroll view is
        // told and the boxes it gets are therefore the same arithmetic. rows:
        // { s, voice, h } -- `voice` is set on a line's FIRST visual row only.
        private function layoutBlock(b:Object, verseW:Number, chorusW:Number,
                                     size:Number, lineH:Number):Object
        {
            var chorus:Boolean = b.kind == 1;
            var wrapW:Number = chorus ? chorusW : verseW;
            var rows:Array = [];
            var lines:Array = b.lines;
            for (var j:int = 0; j < lines.length; j++)
            {
                var ln:Object = lines[j];
                var tag:String = (ln.voice == null || ln.voice.length == 0)
                    ? null : String(ln.voice).toUpperCase();
                var pillW:Number = tag == null ? 0
                    : Math.ceil(HymnWrap.width(tag, MONO, 10.5)) + 18;
                var avail:Number = wrapW - (tag == null ? 0 : pillW + HymnTheme.LINE_GAP);
                if (avail < 80) avail = 80;
                var wrapped:Array = HymnWrap.lines(String(ln.text), avail, SERIF, size);
                for (var r:int = 0; r < wrapped.length; r++)
                {
                    rows.push({ s: String(wrapped[r]), voice: r == 0 ? tag : null, h: lineH });
                }
            }
            var inner:Number = rows.length * lineH + (rows.length > 1 ? (rows.length - 1) * 2 : 0);
            var hgt:Number = chorus
                ? 22 + 14 + 10 + inner + 22   // pad, CHORUS label, gap, lines, pad
                : inner;
            return { rows: rows, h: hgt, chorus: chorus };
        }

        private function blockView(t:HymnTheme, b:Object, bi:int, lay:Object,
                                   lineH:Number, docW:Number):Node
        {
            // The sounding verse keeps its marker and the others dim (upstream DIMMED
            // 0.42). Nothing dims while the transport is stopped -- a page you are
            // reading is not "not yet reached" -- but the marker is always on exactly
            // one block, so a stopped page still shows where playing would resume.
            var cur:Boolean = bi == model.blockIndex;
            var active:Boolean = cur || !model.playing;
            var rows:Array = lay.rows;
            var lines:Array = [];
            for (var i:int = 0; i < rows.length; i++)
            {
                var r:Object = rows[i];
                var kk:String = "ln" + String(bi) + "_" + String(i);
                var kids:Array = [];
                if (r.voice != null)
                {
                    var tag:String = String(r.voice);
                    kids.push(this.plate(tag, { key: kk + "v", family: MONO, size: 10.5, bold: true,
                        padX: 9, h: 20, radius: 999, mt: Math.round((lineH - 20) / 2),
                        bg: t.tint(lay.chorus == true ? t.accentSoft : t.panel, 0.18),
                        fg: t.accent, ariaName: "Voice " + tag }));
                }
                var textW:Number = lay.chorus == true ? docW - 44 : docW - 12 - HymnTheme.GUTTER_W;
                if (r.voice != null)
                {
                    var pw:Number = Math.ceil(HymnWrap.width(String(r.voice), MONO, 10.5)) + 18;
                    textW = textW - pw - HymnTheme.LINE_GAP;
                }
                kids.push(text(String(r.s), { key: kk + "t",
                    style: this.txt(SERIF, model.lyricSize, false, t.text, textW, lineH, "left") }));
                lines.push(row({ key: kk, style: t.LINE }, kids));
            }
            var colKids:Array = [];
            if (lay.chorus == true)
            {
                colKids.push(text("CHORUS", { key: "cl" + String(bi),
                    style: this.txt(SANS, 11, true, t.accent, docW - 44, 14, "left") }));
                colKids.push(column({ key: "cls" + String(bi), style: t.LINES }, lines));
                return box({ key: "bk" + String(bi),
                             style: cur ? t.CHORUS_ON : t.CHORUS, minSize: [null, Length.px(lay.h)] },
                           colKids);
            }
            // Verse: the number sits in a 48pt gutter, offset so the disc is centred on
            // the first line, and the whole row is pulled 14pt left so the 2pt rule can
            // appear WITHOUT the text moving.
            var disc:Array = [];
            if (b.verse > 0)
            {
                disc.push(this.plate(String(b.verse), { key: "d" + String(bi),
                    family: MONO, size: 12, bold: true, padX: 0, w: 28, h: 28, radius: 999,
                    mt: Math.round((lineH - 28) / 2),
                    bg: cur && model.playing ? t.accent : t.raised,
                    fg: cur && model.playing ? t.onAccent : t.text2,
                    ariaName: "Verse " + String(b.verse) }));
            }
            var body:Array = [
                box({ key: "rule" + String(bi), style: cur ? t.VERSE_RULE : t.VERSE_RULE_OFF }),
                column({ key: "g" + String(bi), style: t.GUTTER }, disc),
                column({ key: "ls" + String(bi), style: t.LINES }, lines)
            ];
            return box({ key: "bk" + String(bi), style: t.VERSE }, body);
        }

        private function stageW():Number
        {
            if (this.app != null && this.app.stage != null && this.app.stage.stageWidth > 0)
            {
                return this.app.stage.stageWidth;
            }
            return HymnTheme.WIN_W;
        }

        private function stageH():Number
        {
            if (this.app != null && this.app.stage != null && this.app.stage.stageHeight > 0)
            {
                return this.app.stage.stageHeight;
            }
            return HymnTheme.WIN_H;
        }

        // ---- player -----------------------------------------------------
        private function player(t:HymnTheme):Node
        {
            var self:HymnView = this;
            var h:Object = model.current();
            var tune:Object = model.tuneOf(h);
            var total:Number = 0;
            var elapsed:Number = 0;
            if (h != null)
            {
                for (var i:int = 0; i < h.blocks.length; i++)
                {
                    var d:Number = model.durationOf(h, i);
                    total += d;
                    if (i < model.blockIndex) elapsed += d;
                    else if (i == model.blockIndex) elapsed += model.blockT;
                }
            }

            // ---- left: what is playing ----
            var nowTitle:String = h == null ? "Hymn Book" : String(h.title);
            var nowSub:String = h == null ? "" : "Hymn " + String(h.number) + VOICE_SEP
                + (tune != null ? "with tune" : "no tune");
            var left:Array = [
                this.plate(h == null ? "0" : String(h.number), {
                    key: "plTile", family: MONO, size: 14, bold: true, padX: 0,
                    w: HymnTheme.PL_TILE, h: HymnTheme.PL_TILE, radius: 14,
                    bg: t.accentSoft, fg: t.accent }),
                column({ key: "plCol", style: StyleRefinement.from({
                    flexDirection: "column", flexGrow: 1, flexBasis: 0, size: [null, null],
                    gap: 2, justifyContent: "center" }) }, [
                    text(HymnWrap.fit(nowTitle, 200, SANS, 14.5, true), { key: "plTitle",
                        style: this.txt(SANS, 14.5, true, t.text, 200, 19, "left") }),
                    text(HymnWrap.fit(nowSub, 200, SANS, 12.5), { key: "plSub",
                        style: this.txt(SANS, 12.5, false, t.text3, 200, 16, "left") })
                ])
            ];

            // ---- centre: voices, play, instrument; then clock and map ----
            var parts:Array = ["Soprano", "Alto", "Tenor", "Bass"];
            var letters:Array = ["S", "A", "T", "B"];
            var voices:Array = [];
            for (var v:int = 0; v < 4; v++)
            {
                var muted:Boolean = model.muted[parts[v]] == true;
                voices.push(this.plate(letters[v], {
                    key: "vm" + String(v), family: MONO, size: 12, bold: true, padX: 0,
                    w: 30, h: 30, radius: 999,
                    bg: muted ? t.raised : t.accentSoft, fg: muted ? t.text3 : t.accent,
                    onClick: (function (p:String):Function {
                        return function (e:Object):void { self.model.toggleVoice(p); };
                    })(parts[v]),
                    ariaName: "Mute " + parts[v] }));
            }
            var playBtn:Node = box({ key: "play", style: this.tile(44, 999, t.accent),
                onClick: function (e:Object):void { self.model.togglePlay(); },
                ariaName: model.playing ? "Pause" : "Play" }, [
                icon(model.playing ? I_PAUSE : I_PLAY, { key: "pli",
                    size: [Length.px(17), Length.px(17)], color: t.onAccent,
                    stroke: false, fill: true })
            ]);
            var inst:Array = [];
            var names:Array = ["Organ", "Flute"];
            for (var n2:int = 0; n2 < names.length; n2++)
            {
                var on:Boolean = model.instrument == names[n2];
                inst.push(this.plate(String(names[n2]).toUpperCase(), {
                    key: "in" + String(n2), family: SANS, size: 12, bold: true, padX: 12,
                    h: 28, radius: 999, bg: on ? t.accentSoft : t.raised,
                    fg: on ? t.accent : t.text3,
                    onClick: (function (nm:String):Function {
                        return function (e:Object):void { self.model.setInstrument(nm); };
                    })(names[n2]),
                    ariaName: "Instrument " + names[n2] }));
            }
            // Three siblings -- 4 voice discs, the play button, the instrument pair --
            // 188 + 16 + 44 + 16 + 188 = 452 in a 600pt column. The play button belongs
            // BETWEEN the two groups: pushing it into the voice row is what squeezed it
            // to 39pt wide and put it on the wrong centre line.
            var top:Array = [
                row({ key: "voices", style: t.VOICES }, voices),
                playBtn,
                row({ key: "instr", style: t.INSTR }, inst)
            ];

            // ---- the section map ----
            //
            // Widths are arithmetic, not percentages: a pct child inside a flex_1 row
            // segment is the one shape this engine solves last (see HymnTheme.PL_MAP),
            // and a section map that only settles on the second frame is a visible pop.
            var mapKids:Array = [];
            if (h == null || h.blocks.length == 0 || tune == null)
            {
                mapKids.push(box({ key: "mapNone", style: StyleRefinement.from({
                    size: [Length.pct(1), Length.px(4)], cornerRadii: 2, background: t.raised }) }));
            }
            else
            {
                var nb:int = h.blocks.length;
                var mapW:Number = HymnTheme.PL_CENTER_W - 80 - 20;
                var segsW:Number = mapW - (nb - 1) * HymnTheme.MAP_GAP;
                var avail:Number = segsW - nb * HymnTheme.MAP_MIN_W;
                var sumD:Number = 0;
                for (var q:int = 0; q < nb; q++) sumD += model.durationOf(h, q);
                var acc:Number = 0;
                for (var s2:int = 0; s2 < nb; s2++)
                {
                    var frac:Number = sumD > 0 ? model.durationOf(h, s2) / sumD : 1 / nb;
                    var sw:Number = HymnTheme.MAP_MIN_W + (avail > 0 ? avail * frac : 0);
                    if (s2 == nb - 1) sw = segsW - acc;      // absorb the rounding
                    var w2:Number = Math.floor(sw);
                    acc += w2;
                    var cur:Boolean = s2 == model.blockIndex;
                    var bg2:uint = cur ? t.accent : t.mix(t.accent, t.panel, 0.30);
                    var label:String = h.blocks[s2].kind == 1 ? "C"
                        : (h.blocks[s2].verse > 0 ? String(h.blocks[s2].verse) : String(s2 + 1));
                    var segKids:Array = [];
                    var segStyle:StyleRefinement = StyleRefinement.from({
                        flexDirection: "row", alignItems: "center", justifyContent: "center",
                        size: [Length.px(w2), Length.px(HymnTheme.MAP_H)],
                        cornerRadii: 8, background: bg2
                    });
                    segKids.push(text(label, { key: "ml" + String(s2),
                        style: this.txt(MONO, 10, true, cur ? t.onAccent : t.mix(t.accent, t.panel, 0.75),
                            w2, 14, "center") }));
                    mapKids.push(box({ key: "ms" + String(s2), style: segStyle,
                        onClick: (function (ix:int):Function {
                            return function (e:Object):void {
                                self.model.seekBlock(ix);
                            };
                        })(s2),
                        ariaName: "Section " + String(s2 + 1) }, segKids));
                }
            }
            var mapRow:Array = [
                text(this.clock(elapsed), { key: "tEl",
                    style: this.txt(MONO, 11, false, t.text3, 40, 14, "left"), ariaName: "Elapsed" }),
                row({ key: "map", style: t.PL_MAP, ariaName: "Song map" }, mapKids),
                text("-" + this.clock(total - elapsed), { key: "tRem",
                    style: this.txt(MONO, 11, false, t.text3, 40, 14, "right"), ariaName: "Remaining" })
            ];

            // ---- right: pause-after and the silent-build disclosure ----
            var right:Array = [];
            var dotColor:uint = model.stopEach ? t.accent : t.text3;
            // MEASURED, not guessed: a 160pt box around a 130pt run leaves 30pt of dead
            // space that pushes the label off the column's right edge, and the chip below
            // it lands on a different edge (the screenshot reads that as "not aligned").
            var pauseLabel:String = "Pause after each verse";
            var pauseW:Number = Math.ceil(HymnWrap.width(pauseLabel, SANS, 12, true)) + 1;
            var toggleKids:Array = [
                box({ key: "dot", style: this.dot(8, dotColor) }),
                text(pauseLabel, { key: "pauseT",
                    style: this.txt(SANS, 12, true, model.stopEach ? t.accent : t.text2,
                        pauseW, 16, "left") })
            ];
            right.push(box({ key: "pauseAfter", style: StyleRefinement.from({
                flexDirection: "row", alignItems: "center", justifyContent: "flex-end", gap: 8,
                padding: [0, 12, 0, 12], size: [null, Length.px(30)],
                cornerRadii: 999, background: model.stopEach ? t.accentSoft : t.raised }),
                onClick: function (e:Object):void { self.model.setStopEach(!model.stopEach); },
                ariaName: "Pause after each verse" }, toggleKids));
            var expLabel:String = "SILENT: no audio in this build";
            var expW:Number = Math.ceil(HymnWrap.width(expLabel, SANS, 11)) + 1;
            var expKids:Array = [
                box({ key: "expDot", style: this.dot(6, t.accent) }),
                text(expLabel, { key: "expT",
                    style: this.txt(SANS, 11, false, t.text3, expW, 14, "left") })
            ];
            right.push(row({ key: "exp", style: StyleRefinement.from({
                flexDirection: "row", alignItems: "center", justifyContent: "flex-end", gap: 6,
                padding: [0, 12, 0, 12], size: [null, Length.px(24)], cornerRadii: 999 }) }, expKids));

            var center:Array = [
                row({ key: "plTop", style: t.PL_TOP }, top),
                row({ key: "plMapRow", style: t.PL_MAPROW }, mapRow)
            ];
            return row({ key: "player", style: t.PLAYER, ariaName: "Player" }, [
                row({ key: "plLeft", style: t.PL_LEFT }, left),
                column({ key: "plCenter", style: t.PL_CENTER }, center),
                column({ key: "plRight", style: t.PL_RIGHT }, right)
            ]);
        }

        private function dot(size:Number, color:uint):StyleRefinement
        {
            var ck:String = "dot|" + String(size) + "|" + String(color);
            if (this.texts == null) this.texts = {};
            var s:StyleRefinement = this.texts[ck] as StyleRefinement;
            if (s == null)
            {
                s = StyleRefinement.from({
                    size: [Length.px(size), Length.px(size)], cornerRadii: 999, background: color });
                this.texts[ck] = s;
            }
            return s;
        }

        private function clock(sec:Number):String
        {
            if (sec < 0) sec = 0;
            var s:int = Math.round(sec);
            var m:int = int(s / 60);
            var r:int = s - m * 60;
            var rs:String = String(r);
            if (rs.length < 2) rs = "0" + rs;
            return String(m) + ":" + rs;
        }

        // ---- splash -----------------------------------------------------
        //
        // Hold 1500ms, fade 450ms. The loader bar sweeps a 56pt bar across a 140pt
        // track on an 1100ms loop; the content fades in from 28pt below on a 700ms
        // ease-out-quint. Every one of those numbers is upstream's.
        private function splash(t:HymnTheme):Node
        {
            var phase:Number = 0;      // 0..1 through the current phase
            var opacity:Number = 1;
            if (model.splash == 0)
            {
                phase = Math.min(1, model.splashMs / 700);
            }
            else
            {
                opacity = 1 - Math.min(1, model.splashMs / HymnModel.SPLASH_FADE);
            }
            // ease-out-quint for the entrance, ease-in-out for the exit
            var d:Number = model.splash == 0
                ? 1 - Math.pow(1 - phase, 5)
                : Math.min(1, model.splashMs / HymnModel.SPLASH_FADE);
            var contentOpacity:Number = model.splash == 0 ? d : opacity;
            var rise:Number = Math.round(28 * (1 - (model.splash == 0 ? d : 1)));

            // The loader's own loop: 1100ms, 0..84pt of travel.
            var loop:Number = (model.splashMs % 1100) / 1100;
            var tri:Number = loop < 0.5 ? loop * 2 : 2 - loop * 2;
            var barMl:Number = Math.round(84 * (tri * tri * (3 - 2 * tri)));

            var barStyle:StyleRefinement = StyleRefinement.from({
                size: [Length.px(56), Length.px(3)], cornerRadii: 999,
                background: t.accent, margin: [0, 0, 0, barMl]
            });
            var colStyle:StyleRefinement = StyleRefinement.from({
                flexDirection: "column", alignItems: "center", gap: 8,
                margin: [rise, 0, 0, 0], opacity: contentOpacity
            });
            var overlayStyle:StyleRefinement = StyleRefinement.from({
                position: "absolute", inset: [0, 0, 0, 0],
                alignItems: "center", justifyContent: "center",
                background: t.bg, opacity: opacity
            });
            return box({ key: "splash", style: overlayStyle, ariaName: "Hymn Book" }, [
                column({ key: "splashCol", style: colStyle }, [
                    this.logo(124),
                    this.fixed(10, 14),
                    text("Hymn Book", { key: "spName",
                        style: this.txt(SANS, 26, true, t.text, 200, 34, "center") }),
                    text("Faith Tabernacle", { key: "spSub",
                        style: this.txt(SANS, 13, false, t.text3, 200, 18, "center") }),
                    this.fixed(10, 22),
                    row({ key: "loader", style: StyleRefinement.from({
                        flexDirection: "row", size: [Length.px(140), Length.px(3)],
                        cornerRadii: 999, background: t.raised, overflow: "hidden" }) },
                        [box({ key: "bar", style: barStyle })])
                ])
            ]);
        }
    }
}
