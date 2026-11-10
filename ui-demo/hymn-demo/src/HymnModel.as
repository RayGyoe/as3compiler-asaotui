// hymn/HymnModel.as -- everything the hymn app knows, and nothing it paints.
//
// THE ONE RULE THIS FILE KEEPS: the view never owns state. A click writes the model,
// the model notifies, the view re-renders. That is the library's own contract (see
// kit/asaot/ui/View.as) and it is what makes the app's behaviour readable: "what
// happens when you press play" is answered here, not in a widget.
//
// THE PLAYER RUNS A CLOCK AND A SOUND CARD. The upstream app arranges a 4-part tune
// from <tt>assets/tunes/*.mid</tt> and renders it through rustysynth + a GM SoundFont.
// This port has the same note data compiled in (HymnNotes.as) and synthesises the pass
// itself (HymnSynth) into PCM for flash.media (HymnAudio) -- so the melody, the parts
// and the timing are the tune's own, and only the timbre is ours.
//
// THE CLOCK STAYS THE MODEL'S. The device owns the samples; this file owns the
// timeline the section map, the lyric highlight and the follow animation read. That
// separation is deliberate: seeking, "pause after each verse" and the SIDEBAR all
// move on the frame clock, and the sound is told where to start, not asked where it is.
package hymn
{
    import asaot.ui.Dirty;
    import flash.utils.getTimer;

    public class HymnModel
    {
        public static const ALL_ROWS:String = "all";
        public static const TUNED_ROWS:String = "tuned";

        // ---- data --------------------------------------------------------
        public var hymns:Array = [];
        public var tunes:Object = {};        // number -> {number, length, chorusAt, voices}
        public var ready:Boolean = false;

        // ---- library state ------------------------------------------------
        public var query:String = "";
        public var filter:String = ALL_ROWS;
        // Indices INTO `hymns` (the same shape HymnBook.search returns), recomputed
        // only when the query, the filter or the data changes -- never per frame.
        public var visible:Array = [];
        public var sel:int = 0;              // index into hymns
        public var sidebarOpen:Boolean = true;
        // The list's own scroll offset, in points. The virtual list is row-granular and
        // asks the author to keep this -- it is a MODEL field, not widget state, so a
        // re-render after a click cannot silently jump the list back to the top.
        public var libOffset:Number = 0;

        // ---- appearance ---------------------------------------------------
        public var dark:Boolean = true;
        public var theme:HymnTheme;
        public var light:HymnTheme;
        public var lyricSize:Number = 19;

        // ---- transport ----------------------------------------------------
        public var playing:Boolean = false;
        // Which BLOCK of the selected hymn is sounding, and how far into it.
        public var blockIndex:int = 0;
        public var blockT:Number = 0;
        public var blockDur:Number = 6;
        public var muted:Object = { Soprano: false, Alto: false, Tenor: false, Bass: false };
        public var instrument:String = "Organ";
        // The sound card. Owned by the model because "is it playing" is model state;
        // the view only reads `audio.status` to print what the bar is doing.
        public var audio:HymnAudio = new HymnAudio();
        private var noteRows:Object = {};   // hymn number -> its HymnNotes row
        // Pause at the end of a verse instead of running into the next one. Upstream's
        // "Pause after each verse" (src/app.rs `stop_each`): the transport stops at the
        // block boundary, the reader keeps its place.
        public var stopEach:Boolean = false;

        // ---- window chrome, all of it timed ---------------------------------
        // Upstream: SPLASH_HOLD 1500ms, SPLASH_FADE 450ms, SIDEBAR_SLIDE 300ms.
        public static const SPLASH_HOLD:int = 1500;
        public static const SPLASH_FADE:int = 450;
        public static const SIDE_MS:int = 300;
        public static const FOLLOW_LINE:Number = 0.22;
        public static const FOLLOW_EASE:Number = 0.14;

        // 0 = showing, 1 = fading out, 2 = gone. The splash is not a screenshot
        // nicety: it is why the first frame can allocate the whole hymn book without
        // the user watching an empty window.
        public var splash:int = 0;
        public var splashMs:int = 0;       // ms inside the CURRENT phase
        public var nowMs:int = 0;          // ms since the frame clock started
        // The sidebar SLOT width, animated. 392 = the 380pt pane + the 12pt gap it
        // vacates; the pane itself stays 380 and slides out from under the reader.
        public var sideW:Number = HymnTheme.LIB_W + HymnTheme.GAP;

        // ---- reader scroll ------------------------------------------------
        // The live offset, mirrored from the scroll view, and whether the reader is
        // following the sounding verse (a manual scroll stops the following, exactly
        // like upstream's `follow` flag).
        public var scrollY:Number = 0;
        public var follow:Boolean = true;

        private var listeners:Array = [];
        private var lastMs:int = 0;
        private var bootMs:int = -1;
        private var lastQuery:String = null;
        private var lastFilter:String = null;

        public function HymnModel()
        {
            this.light = new HymnTheme("light");
            this.theme = new HymnTheme("dark");
        }

        // ---- loading ------------------------------------------------------
        // CALLED FROM THE FIRST FRAME, not from the constructor's file scope: building
        // 1000 parsed hymns allocates far more than the collector's offscreen trigger,
        // and a collection *inside* this loop is what compiler-gaps.md G45 is about.
        // Once the frame loop is running the collector only ever marks at a frame
        // boundary, so the whole build happens with no cycle running.
        public function load():void
        {
            this.hymns = HymnBook.load();
            this.parseTunes();
            this.ready = true;
            this.sel = 0;
            this.recompute();
            this.blockDur = this.durationOf(hymns.length > 0 ? hymns[0] : null, 0);
            this.notify(Dirty.ALL);
        }

        private function parseTunes():void
        {
            var out:Object = {};
            var rows:Array = HymnTunes.RAW;
            for (var i:int = 0; i < rows.length; i++)
            {
                var parts:Array = String(rows[i]).split("\t");
                if (parts.length < 4) continue;
                out[parseInt(parts[0], 10)] = {
                    number: parseInt(parts[0], 10),
                    length: Number(parts[1]),
                    chorusAt: Number(parts[2]),
                    voices: String(parts[3])
                };
            }
            this.tunes = out;
            // The notes are kept as their raw row and parsed on selection: only the
            // hymn being played needs them, and 52k notes parsed at start-up would be
            // work done for nothing.
            var noteList:Array = HymnNotes.RAW;
            for (i = 0; i < noteList.length; i++)
            {
                var row:String = String(noteList[i]);
                var tab:int = row.indexOf("\t");
                if (tab < 0) continue;
                this.noteRows[parseInt(row.substring(0, tab), 10)] = row;
            }
        }

        // ---- derived --------------------------------------------------
        public function current():Object
        {
            if (sel < 0 || sel >= hymns.length) return null;
            return hymns[sel];
        }

        public function tuneOf(hymn:Object):Object
        {
            if (hymn == null) return null;
            return tunes[hymn.number];
        }

        public function tunedCount():int
        {
            var n:int = 0;
            for (var i:int = 0; i < hymns.length; i++)
            {
                if (tunes[hymns[i].number] != null) n++;
            }
            return n;
        }

        public function hasTuneSelected():Boolean
        {
            return tuneOf(current()) != null;
        }

        // Seconds for one block of `hymn`: the tune's one-pass length divided by the
        // number of blocks, so the section map advances at the arrangement's own pace.
        // A hymn without a tune gets a reading pace instead -- the reader still walks
        // the verses, and the UI says there is no tune.
        public function durationOf(hymn:Object, block:int):Number
        {
            if (hymn == null) return 6;
            var tune:Object = tuneOf(hymn);
            if (tune == null) return 6;
            var n:int = hymn.blocks.length;
            if (n < 1) n = 1;
            var d:Number = tune.length / n;
            return d > 1.2 ? d : 1.2;
        }

        // ---- library mutation -----------------------------------------
        public function setQuery(q:String):void
        {
            this.query = q == null ? "" : q;
            this.recompute();
            this.notify(Dirty.ALL);
        }

        public function setLibOffset(y:Number):void
        {
            if (this.libOffset == y) return;
            this.libOffset = y;
            this.notify(Dirty.VALUE);
        }

        public function setFilter(f:String):void
        {
            if (this.filter == f) return;
            this.filter = f;
            this.recompute();
            this.notify(Dirty.ALL);
        }

        public function pick(hymnIndex:int):void
        {
            if (hymnIndex < 0 || hymnIndex >= hymns.length) return;
            this.sel = hymnIndex;
            this.blockIndex = 0;
            this.blockT = 0;
            this.blockDur = durationOf(hymns[hymnIndex], 0);
            // Upstream's `load_tune` is documented "Replace the current tune (stops
            // playback)", and `select()` goes through it: picking another hymn ends the
            // old one rather than cross-fading into it. It also keeps the sound card from
            // rendering a new PCM image per keystroke while the list is walked.
            this.playing = false;
            this.openTune();
            this.notify(Dirty.ALL);
        }

        // Hand the newly selected hymn's notes to the sound card. No render yet: the
        // PCM image is built on play, with the parts and instrument in force then.
        private function openTune():void
        {
            var h:Object = current();
            var t:Object = tuneOf(h);
            if (t == null)
            {
                this.audio.close();
                return;
            }
            this.audio.open(String(this.noteRows[h.number]), t.length);
        }

        // Where the timeline is, in seconds -- the number the device is given when it
        // has to (re)start, so a seek or an unmute lands exactly where the map shows.
        public function nowSec():Number
        {
            var h:Object = current();
            if (h == null) return 0;
            var acc:Number = blockT;
            for (var i:int = 0; i < blockIndex && i < h.blocks.length; i++) acc += durationOf(h, i);
            return acc;
        }

        // S/A/T/B as the synthesiser wants them, in track order.
        public function partMask():Array
        {
            var t:Object = tuneOf(current());
            var names:Array = t == null ? [] : String(t.voices).split(",");
            var out:Array = [];
            for (var i:int = 0; i < 4; i++)
            {
                var name:String = i < names.length ? names[i] : "";
                out.push(name != "" && muted[name] != true);
            }
            return out;
        }

        // Re-render and keep going from where the clock is. Used by the part and
        // instrument toggles: the mix changes, the song must not.
        private function restartAudio():void
        {
            if (!playing) return;
            if (!this.audio.play(this.nowSec(), this.partMask(), this.instrument))
            {
                this.playing = false;
                this.notify(Dirty.ALL);
            }
        }

        // `recompute` is the ONLY place `visible` is written. It is called from the
        // three writers above, never from render(): a describe pass must not run the
        // search, or a reflow (a resize) would re-rank the list under the user.
        private function recompute():void
        {
            if (lastQuery == query && lastFilter == filter && visible.length > 0)
            {
                // A no-op query/filter change must not spend 1000 indexOf calls.
                var same:Array = HymnBook.search(hymns, query);
                if (same.length == visible.length)
                {
                    var eq:Boolean = true;
                    for (var k:int = 0; k < same.length; k++)
                    {
                        if (same[k] != visible[k]) { eq = false; break; }
                    }
                    if (eq) return;
                }
            }
            lastQuery = query;
            lastFilter = filter;
            var hits:Array = HymnBook.search(hymns, query);
            var out:Array = [];
            for (var i:int = 0; i < hits.length; i++)
            {
                var ix:int = hits[i];
                if (filter == TUNED_ROWS && tunes[hymns[ix].number] == null) continue;
                out.push(ix);
            }
            this.visible = out;
        }

        // ---- appearance -----------------------------------------------
        public function toggleTheme():void
        {
            this.dark = !this.dark;
            this.theme = this.dark ? new HymnTheme("dark") : light;
            if (this.theme == null) this.theme = new HymnTheme(this.dark ? "dark" : "light");
            this.notify(Dirty.ALL);
        }

        public function setLyricSize(px:Number):void
        {
            var v:Number = Math.round(px);
            if (v < 16) v = 16;
            if (v > 34) v = 34;
            if (v == this.lyricSize) return;
            this.lyricSize = v;
            this.notify(Dirty.ALL);
        }

        public function toggleSidebar():void
        {
            this.sidebarOpen = !this.sidebarOpen;
            this.notify(Dirty.ALL);
        }

        // ---- transport -------------------------------------------------
        public function togglePlay():void
        {
            var h:Object = current();
            if (h == null) return;
            var tune:Object = tuneOf(h);
            if (!this.playing && tune == null)
            {
                // No tune: nothing to play. The bar already says so; do not start a
                // clock that would look like playback.
                return;
            }
            this.playing = !this.playing;
            if (this.playing)
            {
                this.blockDur = durationOf(h, blockIndex);
                this.lastMs = getTimer();
                if (!this.audio.play(this.nowSec(), this.partMask(), this.instrument))
                {
                    this.playing = false;
                }
            }
            else
            {
                this.audio.stop();
            }
            this.notify(Dirty.ALL);
        }

        public function stop():void
        {
            this.playing = false;
            this.blockIndex = 0;
            this.blockT = 0;
            this.audio.stop();
            this.notify(Dirty.ALL);
        }

        public function step(dir:int):void
        {
            var h:Object = current();
            if (h == null) return;
            var n:int = h.blocks.length;
            if (n == 0) return;
            this.blockIndex = (this.blockIndex + dir + n) % n;
            this.blockT = 0;
            this.blockDur = durationOf(h, blockIndex);
            this.restartAudio();
            this.notify(Dirty.ALL);
        }

        // Jump to a section: the transport's own verb, so the map is not poking at
        // three fields and notifying behind the model's back.
        public function seekBlock(ix:int):void
        {
            var h:Object = current();
            if (h == null || ix < 0 || ix >= h.blocks.length) return;
            this.blockIndex = ix;
            this.blockT = 0;
            this.blockDur = durationOf(h, ix);
            this.restartAudio();
            this.notify(Dirty.ALL);
        }

        public function setInstrument(name:String):void
        {
            if (this.instrument == name) return;
            this.instrument = name;
            this.restartAudio();
            this.notify(Dirty.ALL);
        }

        public function toggleVoice(part:String):void
        {
            if (muted[part] == null) return;
            muted[part] = !muted[part];
            this.restartAudio();
            this.notify(Dirty.ALL);
        }

        public function setStopEach(v:Boolean):void
        {
            if (this.stopEach == v) return;
            this.stopEach = v;
            this.notify(Dirty.VALUE);
        }

        // ---- reader scroll ------------------------------------------------
        // The scroll view's live offset, mirrored back. The `echo` argument is the
        // value this app DECLARED last frame: the widget calls onScroll for its own
        // programmatic moves too, so without that comparison the follow animation would
        // read its own output as a user gesture and switch itself off on the first frame.
        public var declaredScroll:Number = 0;
        public var blockY:Number = 0;      // y of the sounding block, published by the view
        public var viewH:Number = 0;       // reader viewport height, published by the view
        public var maxScroll:Number = 0;

        public function setScrollY(y:Number, echo:Number):void
        {
            if (Math.abs(y - echo) < 1.5) return;   // our own request landing
            this.scrollY = y;
            this.follow = false;
        }

        public function reattachFollow():void
        {
            this.follow = true;
            this.notify(Dirty.ALL);
        }

        // The frame clock. ONE entry point, driven by the app's own ENTER_FRAME, so a
        // describe pass never advances time (a resize would otherwise skip a verse).
        //
        // The chrome's own clocks live here too (splash, sidebar slide, follow-scroll):
        // an animation is a STATE change, so it goes through notify() and the view never
        // has to keep a timer of its own -- one clock, one direction.
        public function tick(nowMs:int):void
        {
            if (bootMs < 0) { bootMs = nowMs; lastMs = nowMs; }
            var dtMs:int = nowMs - lastMs;
            if (dtMs < 0) dtMs = 0;
            if (dtMs > 500) dtMs = 500;
            lastMs = nowMs;
            this.nowMs = nowMs - bootMs;

            var dirty:int = 0;

            // ---- splash: hold, fade, gone ---------------------------------
            if (splash < 2)
            {
                splashMs += dtMs;
                if (splash == 0 && splashMs >= SPLASH_HOLD)
                {
                    splash = 1;
                    splashMs = 0;
                }
                else if (splash == 1 && splashMs >= SPLASH_FADE)
                {
                    splash = 2;
                }
                // The loader bar moves for the whole hold, so every tick of this phase
                // needs a frame even when nothing else about it changed.
                dirty = splash == 2 ? Dirty.ALL : Dirty.VALUE;
            }

            // ---- sidebar slide -------------------------------------------
            var want:Number = sidebarOpen ? HymnTheme.LIB_W + HymnTheme.GAP : 0;
            if (sideW != want)
            {
                var step:Number = (HymnTheme.LIB_W + HymnTheme.GAP) * dtMs / SIDE_MS;
                if (sideW < want) { sideW += step; if (sideW > want) sideW = want; }
                else { sideW -= step; if (sideW < want) sideW = want; }
                dirty = Dirty.ALL;
            }

            // ---- transport -------------------------------------------------
            if (playing)
            {
                var h:Object = current();
                if (h == null)
                {
                    playing = false;
                    this.audio.stop();
                    dirty = Dirty.ALL;
                }
                else
                {
                    var n:int = h.blocks.length;
                    blockT += dtMs / 1000;
                    while (blockT >= blockDur)
                    {
                        blockT -= blockDur;
                        blockIndex++;
                        if (blockIndex >= n)
                        {
                            // Upstream's engine resets `pos = 0` when the tune runs out
                            // (`synth.rs` completion branch: pos 0, next 0, halt), so the
                            // map and the follow animation go back to the first verse and
                            // the next play starts from the top. Holding the last block
                            // would leave a play button that replays only verse N.
                            blockIndex = 0;
                            blockT = 0;
                            blockDur = durationOf(h, 0);
                            playing = false;
                            // The device would run out of samples on its own; stopping
                            // it here is what keeps the sound and the map agreeing at
                            // the end of the last verse.
                            this.audio.stop();
                            dirty = Dirty.ALL;
                            break;
                        }
                        if (stopEach)
                        {
                            // Pause ON the boundary: the next verse is now current, and
                            // play resumes from it.
                            blockT = 0;
                            playing = false;
                            this.audio.stop();
                            dirty = Dirty.ALL;
                            break;
                        }
                        blockDur = durationOf(h, blockIndex);
                        dirty = Dirty.ALL;
                    }
                    if (dirty == 0) dirty = Dirty.VALUE;
                }
            }

            // ---- follow the sounding verse --------------------------------
            if (playing && follow && viewH > 0)
            {
                var target:Number = blockY - viewH * FOLLOW_LINE;
                if (target < 0) target = 0;
                if (target > maxScroll) target = maxScroll;
                var gap:Number = target - scrollY;
                if (gap > 0.5 || gap < -0.5)
                {
                    // Eased per 60Hz frame, corrected for the real frame time: the same
                    // curve at 30 or 120 Hz.
                    scrollY += gap * Math.min(1, FOLLOW_EASE * dtMs / 16.67);
                    dirty = Dirty.ALL;
                }
            }

            if (dirty != 0) this.notify(dirty);
        }

        // How far through the CURRENT block, 0..1 -- the song map's fill.
        public function blockProgress():Number
        {
            if (blockDur <= 0) return 0;
            var p:Number = blockT / blockDur;
            return p < 0 ? 0 : (p > 1 ? 1 : p);
        }

        // ---- observer plumbing ----------------------------------------
        public function subscribe(fn:Function):void
        {
            listeners.push(fn);
        }

        public function notify(dirty:int):void
        {
            for (var i:int = 0; i < listeners.length; i++)
            {
                var fn:Function = listeners[i];
                fn(dirty);
            }
        }
    }
}
