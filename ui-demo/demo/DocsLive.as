// demo/DocsLive -- the "live" page: 22 ticking quotes, 22 sparklines and the frame
// counters the app publishes, all in one board.
//
// WHY THIS PAGE EXISTS
// --------------------
// The reference gallery opens on an app, not on a component: a watchlist proves in
// three seconds what a page of prose cannot -- the toolkit redraws a moving list at
// a steady frame rate without dropping the layout. This is that page, and it is the
// app's landing page (DocsCatalog.LANDING).
//
// IT IS NOT A SPECIAL CASE INSIDE THE SHELL. The board is a DocSection like any
// other: `render()` returns factories, the widgets report to `DocsModel`, and the
// only thing the shell does for it is `frameTick()` -- one ENTER_FRAME listener that
// steps the market and re-notifies. Everything the board shows comes from
// LiveMarket, and everything it says about cost comes from `UiApp`'s own pass
// counters (describeCalls / paintPasses / layoutSolves), not from a stopwatch of our
// own invention.
//
// THE ONE STYLE DEPARTURE is `wide: true` on the board's section: the demo surface
// loses its padding, border and tint so the board fills it edge to edge, the way an
// app would. The height arithmetic is untouched (DocSection.demoH is still the
// surface's height), which is what keeps the tour's "no child outside its block"
// sweep valid.
package demo
{
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.box;
    import asaot.ui.button;
    import asaot.ui.column;
    import asaot.ui.row;
    import asaot.ui.scrollView;
    import asaot.ui.sparkline;
    import asaot.ui.style.Length;
    import asaot.ui.style.StyleRefinement;
    import asaot.ui.tabs;
    import asaot.ui.text;

    public final class DocsLive
    {
        // The market's own voice: green / red / grey. Hardcoded, like the rest of
        // the docs palette (DocsDemo) -- a demo must not retint with a theme, or a
        // screenshot of "up" would be a screenshot of something else.
        private static const UP:uint = 0x15803D;
        private static const DOWN:uint = 0xB91C1C;
        private static const FLAT:uint = 0x64748B;
        private static const INK:uint = 0x0F172A;
        private static const MUTED:uint = 0x64748B;
        private static const HAIR:uint = 0xE2E8F0;

        // Board geometry. The strip / filter / header / footer are fixed, so the
        // list gets whatever the surface leaves: at the docs window that is
        // 500 - 54 - 36 - 22 - 24 = 364, i.e. seven 52pt rows.
        private static const BOARD_H:Number = 500;
        private static const ROW_H:Number = 52;
        private static const STRIP_H:Number = 54;
        private static const FILTER_H:Number = 36;
        private static const HEAD_H:Number = 22;
        private static const FOOT_H:Number = 24;
        private static const LIST_H:Number = BOARD_H - STRIP_H - FILTER_H - HEAD_H - FOOT_H;
        // The quote column's width. ONE number: the row's price cell and TWO of the
        // header's cells are 160 wide together, which is what makes the header line up
        // over the rows. (It was 80 + 80 in the header against a single 80 in the row,
        // so every header label sat 80px left of the column it named -- visible the
        // moment the board was drawn.)
        private static const PRICE_W:Number = 160;

        private static const C_TITLE:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(13)],
            text: { fontSize: 13, fontWeight: "bold", color: INK }
        });
        private static const C_NAME:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(13)],
            text: { fontSize: 11, color: MUTED }
        });
        private static const C_LAST:StyleRefinement = StyleRefinement.from({
            size: [Length.px(PRICE_W), Length.px(17)],
            text: { fontSize: 13, fontWeight: "bold", color: INK, textAlign: "right" }
        });
        private static const C_CHG:StyleRefinement = StyleRefinement.from({
            size: [Length.px(PRICE_W), Length.px(14)],
            text: { fontSize: 11, fontWeight: "bold", textAlign: "right" }
        });
        private static const CAP:StyleRefinement = StyleRefinement.from({
            size: [Length.px(PRICE_W), Length.px(12)],
            text: { fontSize: 9, fontWeight: "bold", color: 0x94A3B8, textAlign: "right" }
        });
        private static const TILE:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", flexGrow: 1, flexBasis: 0,
            size: [null, Length.px(58)], padding: [8, 10], gap: 2,
            background: 0xFFFFFF, borderWidths: 1, borderColor: HAIR, cornerRadii: 8
        });
        private static const TILE_LABEL:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(12)],
            text: { fontSize: 9, fontWeight: "bold", color: 0x94A3B8 }
        });
        private static const TILE_VALUE:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(24)],
            text: { fontSize: 19, fontWeight: "bold", color: INK }
        });

        public static function sections(view:DocsView, id:String):Array
        {
            if (id != "live") return null;
            var m:DocsModel = view.model;

            return [
                new DocSection("A live board", [
                    "Twenty-two quotes, twenty-two sparklines and a composite index, redrawn ten times a second.",
                    "The rows are rebuilt from the model on every tick -- no widget caches a quote, nothing is patched behind the reconciler's back. The list beneath scrolls like any other: it is a scrollView."
                ], [
                    "row({ style: ROW }, [",
                    "    column({ style: NAME_COL }, [text(s.code), text(s.name)]),",
                    "    sparkline({ values: s.series, version: s.rev, fill: true,",
                    "                color: s.chg < 0 ? DOWN : UP, baseline: s.prev,",
                    "                style: { size: [104, 34] } }),",
                    "    column({ style: PRICE_COL }, [text(price(s.last)), text(signed(s.chg))])",
                    "])"
                ], BOARD_H, function ():Node { return board(view); }, true),

                new DocSection("What a frame costs", [
                    "These are the app's own numbers, sampled once a second: the frames it actually drew, the nodes it holds, how many describe / paint passes it ran, and the per-pass average of the two phases that cost anything. A tick that changes a VALUE runs describe -> measure -> solve -> arrange -> paint; a tick"
                ], [
                    "// UiApp publishes the counters; the page only reads them",
                    "var fps:int = view.fps;                      // frames drawn / second",
                    "var nodes:int = view.nodeCount;              // retained nodes in the tree",
                    "var solve:Number = (app.profSolveMs - s0) / (app.layoutSolves - l0);",
                    "var paint:Number = (app.profPaintMs - q0) / (app.paintPasses - p0);"
                ], 76, function ():Node { return stats(view); }),

                new DocSection("Pause, resume, reset", [
                    "The market is driven by the app's frame clock, not by a timer of its own: `frameTick()` steps it and calls `model.notify(Dirty.VALUE)`. Pausing is therefore one boolean in the model -- and a paused board proves the loop really is idle, because the paint counter stops moving."
                ], [
                    "if (now - _lastStep < LiveMarket.TICK_MS) return;",
                    "_lastStep = now;",
                    "market.step();",
                    "model.notify(Dirty.VALUE);   // one write, one invalidate, one reflow"
                ], 76, function ():Node { return controls(view); })
            ];
        }

        // ---- the board -------------------------------------------------------

        private static function board(view:DocsView):Node
        {
            var m:DocsModel = view.model;
            var mk:LiveMarket = view.market;
            var rows:Array = ordered(mk, int(m.num("live.f", 0)));
            var list:Array = [];
            for (var i:int = 0; i < rows.length; i++)
            {
                list.push(stockRow(rows[i], i == 0));
            }
            var listH:Number = rows.length * ROW_H;
            if (listH < LIST_H) listH = LIST_H;
            var col:StyleRefinement = StyleRefinement.from({
                flexDirection: "column", size: [Length.pct(1), Length.px(listH)], gap: 0
            });

            return column({ key: "liveBoard", style: StyleRefinement.from({
                flexDirection: "column", size: [Length.pct(1), Length.px(BOARD_H)],
                background: 0xFFFFFF
            }) }, [
                strip(view),
                filterRow(view, rows.length),
                headerRow(),
                scrollView({ key: "liveScroll", style: StyleRefinement.from({
                    flexGrow: 1, flexBasis: 0, size: [Length.pct(1), null]
                }), scrollbarGutter: "stable", barThickness: 8,
                   scrollbarX: "never", wheelStep: ROW_H }, [
                    column({ key: "liveRows", style: col }, list)
                ]),
                text(footNote(view, rows.length), { key: "liveFoot", style: StyleRefinement.from({
                    size: [Length.pct(1), Length.px(FOOT_H)], padding: [0, 14],
                    text: { fontSize: 10, color: 0x94A3B8 }
                }), ariaName: "" })
            ]);
        }

        // The composite, its change, the breadth bar, the session clock and the
        // pause control. Everything is driven by the model, so a paused market
        // repaints exactly once (to swap the button's label).
        private static function strip(view:DocsView):Node
        {
            var m:DocsModel = view.model;
            var mk:LiveMarket = view.market;
            var chg:Number = (mk.level - LiveMarket.INDEX_BASE) / LiveMarket.INDEX_BASE * 100;
            var running:Boolean = m.bool("live.run", true);

            return row({ key: "liveStrip", style: StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: 10,
                size: [Length.pct(1), Length.px(STRIP_H)], padding: [0, 14],
                borderWidths: [0, 0, 1, 0], borderColor: HAIR
            }) }, [
                text("COMPOSITE", { style: StyleRefinement.from({
                    size: [Length.px(64), Length.px(12)],
                    text: { fontSize: 9, fontWeight: "bold", color: 0x94A3B8 } }), ariaName: "" }),
                text(LiveMarket.grouped(mk.level), { key: "liveLevel", style: StyleRefinement.from({
                    size: [Length.px(88), Length.px(20)],
                    text: { fontSize: 16, fontWeight: "bold", color: INK } }), ariaName: "" }),
                text(LiveMarket.signed(chg) + "%", { key: "liveChg", style: StyleRefinement.from({
                    size: [Length.px(60), Length.px(16)],
                    text: { fontSize: 12, fontWeight: "bold", color: toneOf(chg) } }), ariaName: "" }),
                breadthBar(mk),
                text(String(mk.up) + " up", { style: StyleRefinement.from({
                    size: [Length.px(34), Length.px(12)],
                    text: { fontSize: 10, color: UP } }), ariaName: "" }),
                text(String(mk.down) + " dn", { style: StyleRefinement.from({
                    size: [Length.px(34), Length.px(12)],
                    text: { fontSize: 10, color: DOWN } }), ariaName: "" }),
                box({ style: StyleRefinement.from({ flexGrow: 1, flexBasis: 0, size: [null, 1] }) }, []),
                text(LiveMarket.time(mk.clock), { key: "liveClock", style: StyleRefinement.from({
                    size: [Length.px(62), Length.px(14)],
                    text: { fontFamily: "Courier New", fontSize: 11, color: MUTED, textAlign: "right" } }), ariaName: "" }),
                button({ key: "liveRun", label: running ? "Pause" : "Resume",
                         style: StyleRefinement.from({
                             size: [Length.px(62), Length.px(26)], cornerRadii: 6,
                             background: running ? 0xFFFFFF : 0x2563EB,
                             borderColor: running ? 0xD1D5DB : 0x1D4ED8,
                             text: { fontSize: 11, fontWeight: "bold",
                                     color: running ? 0x334155 : 0xFFFFFF } }),
                         onClick: function ():void { m.put("live.run", !running); } })
            ]);
        }

        // Advancers / unchanged / decliners as one proportional bar. A segment whose
        // count is ZERO IS NOT DRAWN -- a 2pt floor used to stand in for it, and a grey
        // sliver of "nothing" between green and red reads as a gap in the data. Dropping
        // the box is also the only form that cannot produce a zero-width rect (the
        // tour treats a zero rect as a layout bug, and it would be right to).
        private static function breadthBar(mk:LiveMarket):Node
        {
            var total:int = mk.up + mk.flat + mk.down;
            if (total < 1) total = 1;
            var W:Number = 84;
            var segs:Array = [];
            if (mk.up > 0) segs.push(seg(W * mk.up / total, UP, "liveBUp"));
            if (mk.flat > 0) segs.push(seg(W * mk.flat / total, 0x94A3B8, "liveBFlat"));
            if (mk.down > 0) segs.push(seg(W * mk.down / total, DOWN, "liveBDn"));
            return row({ key: "liveBreadth", style: StyleRefinement.from({
                flexDirection: "row", gap: 2, size: [Length.px(W), Length.px(8)] }) }, segs);
        }

        private static function seg(w:Number, c:uint, k:String):Node
        {
            return box({ key: k, style: StyleRefinement.from({
                size: [Length.px(w), Length.px(8)], background: c, cornerRadii: 2 }) }, []);
        }

        private static function filterRow(view:DocsView, shown:int):Node
        {
            var m:DocsModel = view.model;
            var mk:LiveMarket = view.market;
            var labels:Array = [
                "All " + mk.rows.length, "Gainers " + mk.up, "Losers " + mk.down, "Active"
            ];
            return row({ key: "liveFilters", style: StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: 10,
                size: [Length.pct(1), Length.px(FILTER_H)], padding: [0, 14]
            }) }, [
                tabs(labels, { key: "liveTabs",
                    style: StyleRefinement.from({ size: [Length.px(272), Length.px(26)] }),
                    selectedIndex: int(m.num("live.f", 0)), gap: 4,
                    onChange: function (i:int):void { m.put("live.f", i); } }),
                box({ style: StyleRefinement.from({ flexGrow: 1, flexBasis: 0, size: [null, 1] }) }, []),
                text(shown + " shown", { style: StyleRefinement.from({
                    size: [Length.px(60), Length.px(12)],
                    text: { fontSize: 10, color: 0x94A3B8, textAlign: "right" } }), ariaName: "" })
            ]);
        }

        private static function headerRow():Node
        {
            return row({ key: "liveHead", style: StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: 12,
                size: [Length.pct(1), Length.px(HEAD_H)], padding: [0, 14],
                borderWidths: [0, 0, 1, 0], borderColor: HAIR
            }) }, [
                text("SYMBOL", { style: StyleRefinement.from({
                    size: [Length.pct(1), Length.px(12)], flexGrow: 1, flexBasis: 0,
                    text: { fontSize: 9, fontWeight: "bold", color: 0x94A3B8 } }), ariaName: "" }),
                text("TODAY", { style: StyleRefinement.from({
                    size: [Length.px(104), Length.px(12)],
                    text: { fontSize: 9, fontWeight: "bold", color: 0x94A3B8, textAlign: "center" } }), ariaName: "" }),
                text("LAST / CHG%", { style: CAP, ariaName: "" })
            ]);
        }

        // One row. A METHOD, not a closure built inside the loop: an AS3 closure
        // captures the VARIABLE, and `var` is function-scoped, so a row built in a
        // loop would report the last symbol for all 22 of them.
        private static function stockRow(s:Object, first:Boolean):Node
        {
            var chg:Number = Number(s.chg);
            var tone:uint = toneOf(chg);
            var series:Array = s.series as Array;
            return row({ key: "liveRow:" + String(s.code), style: StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: 12,
                size: [Length.pct(1), Length.px(ROW_H)], padding: [0, 14],
                borderWidths: first ? [0, 0, 0, 0] : [0, 0, 1, 0], borderColor: 0xF1F5F9
            }) }, [
                column({ style: StyleRefinement.from({
                    flexDirection: "column", gap: 2, flexGrow: 1, flexBasis: 0, size: [null, Length.px(32)] }) }, [
                    text(String(s.code), { style: C_TITLE, ariaName: "" }),
                    text(String(s.name), { style: C_NAME, ariaName: "" })
                ]),
                sparkline({ key: "liveSp:" + String(s.code),
                            values: series, version: int(s.rev),
                            color: tone, fill: true, baseline: Number(s.prev),
                            strokeWidth: 1.5, style: StyleRefinement.from({
                                size: [Length.px(104), Length.px(34)] }) }),
                column({ style: StyleRefinement.from({
                    flexDirection: "column", gap: 2, alignItems: "flex-end",
                    size: [Length.px(PRICE_W), Length.px(32)] }) }, [
                    text(LiveMarket.price(Number(s.last)), { style: C_LAST, ariaName: "" }),
                    text(LiveMarket.signed(chg) + "%", { style: C_CHG.withPatch(
                        StyleRefinement.from({ text: { color: tone } })), ariaName: "" })
                ])
            ]);
        }

        private static function footNote(view:DocsView, shown:int):String
        {
            var mk:LiveMarket = view.market;
            return "Simulated quotes - fiction, not data - " + shown + " of " + mk.rows.length
                + " rows - " + LiveMarket.TICK_MS + " ms tick - "
                + (shown * (1000 / LiveMarket.TICK_MS)) + " updates/s - "
                + (view.sampled ? view.fps + " fps" : "— fps")
                + " - " + view.nodeCount + " nodes";
        }

        // ---- the counters ----------------------------------------------------

        private static function stats(view:DocsView):Node
        {
            // A dash, not a 0: see DocsView.sampled. The node count is real from the
            // first tick, so it needs no such guard.
            return row({ key: "liveStats", style: StyleRefinement.from({
                flexDirection: "row", gap: 8, size: [Length.pct(1), Length.px(58)] }) }, [
                tile("FRAMES / S", rate(view, String(view.fps)), "liveStatFps"),
                tile("RETAINED NODES", String(view.nodeCount), "liveStatNodes"),
                tile("DESCRIBES / S", rate(view, String(view.describesPerSec)), "liveStatDesc"),
                tile("PAINTS / S", rate(view, String(view.paintsPerSec)), "liveStatPaint"),
                tile("SOLVE ms", rate(view, view.solveMs.toFixed(2)), "liveStatSolve"),
                tile("PAINT ms", rate(view, view.paintMs.toFixed(2)), "liveStatPaintMs")
            ]);
        }

        private static function rate(view:DocsView, value:String):String
        {
            return view.sampled ? value : "—";
        }

        private static function tile(label:String, value:String, key:String):Node
        {
            return column({ key: key, style: TILE }, [
                text(label, { style: TILE_LABEL, ariaName: "" }),
                text(value, { style: TILE_VALUE, ariaName: "" })
            ]);
        }

        private static function controls(view:DocsView):Node
        {
            var m:DocsModel = view.model;
            var running:Boolean = m.bool("live.run", true);
            return row({ key: "liveCtl", style: StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: 10, size: [Length.pct(1), Length.px(32)] }) }, [
                button({ key: "liveBtnRun", label: running ? "Pause the market" : "Resume the market",
                         style: StyleRefinement.from({
                             size: [Length.px(150), Length.px(32)], cornerRadii: 8,
                             background: running ? 0xFFFFFF : 0x2563EB,
                             borderColor: running ? 0xD1D5DB : 0x1D4ED8,
                             text: { fontSize: 12, fontWeight: "bold",
                                     color: running ? 0x334155 : 0xFFFFFF } }),
                         onClick: function ():void { m.put("live.run", !running); } }),
                button({ key: "liveBtnReset", label: "Reset the session",
                         style: StyleRefinement.from({
                             size: [Length.px(140), Length.px(32)], cornerRadii: 8,
                             background: 0xFFFFFF, borderColor: 0xD1D5DB,
                             text: { fontSize: 12, color: 0x334155 } }),
                         onClick: function ():void { view.market.reset(); m.notify(Dirty.VALUE); } }),
                text("100 ms per tick - 22 symbols - a full session in about 13 minutes",
                    { style: StyleRefinement.from({
                        size: [Length.pct(1), Length.px(14)], flexGrow: 1, flexBasis: 0,
                        text: { fontSize: 11, color: MUTED } }), ariaName: "" })
            ]);
        }

        // ---- data ------------------------------------------------------------

        // The filter: 0 all, 1 gainers, 2 losers, 3 the ten most traded. Sorting
        // copies the array -- `rows` belongs to the market and its order is the
        // market's, not the view's.
        public static function ordered(mk:LiveMarket, filter:int):Array
        {
            var all:Array = mk.rows.slice();
            if (filter == 1)
            {
                all = all.filter(function (s:Object, i:int, a:Array):Boolean { return Number(s.chg) > 0; });
                all.sort(function (a:Object, b:Object):Number {
                    return Number(b.chg) - Number(a.chg);
                });
            }
            else if (filter == 2)
            {
                all = all.filter(function (s:Object, i:int, a:Array):Boolean { return Number(s.chg) < 0; });
                all.sort(function (a:Object, b:Object):Number {
                    return Number(a.chg) - Number(b.chg);
                });
            }
            else if (filter == 3)
            {
                all.sort(function (a:Object, b:Object):Number {
                    return Number(b.turn) - Number(a.turn);
                });
                all = all.slice(0, 10);
            }
            return all;
        }

        private static function toneOf(chg:Number):uint
        {
            if (chg > 0.005) return UP;
            if (chg < -0.005) return DOWN;
            return FLAT;
        }
    }
}