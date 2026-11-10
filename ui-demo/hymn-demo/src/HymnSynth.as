// HymnSynth: one pass of a tune, synthesised from its note table.
//
// WHY NOT A SOUNDFONT. Upstream renders the bundled MIDI through rustysynth and a
// General MIDI SoundFont (TimGM6mb, 6 MB). This build has no sampler and no asset
// file beside the executable, so it does the two GM programs the player can choose
// (19 church organ, 73 flute) as ADDITIVE waves: one cycle per note, summed from the
// organ's drawbars / the flute's fundamental, played back at the note's own rate.
// That is a smaller instrument than a sampled organ, not a stand-in that pretends to
// be one -- and it is the only way to have sound from compiled-in data alone.
//
// WHAT IS FAITHFUL. The note times and pitches come from the tunes' own MIDI files
// (hymn-data.cjs freezes the tempo map into centiseconds), so the melody, the parts
// and the timing are the real ones. Only the timbre is ours.
//
// Resolution: 22050 Hz mono float. The highest partial is the 4th harmonic of a
// soprano line (about 4 kHz), well under the 11 kHz Nyquist limit, so half the
// device rate costs nothing audible and halves both the render time and the PCM
// image the audio backend has to hold.
package hymn
{
    import flash.utils.ByteArray;
    import flash.utils.getTimer;

    public final class HymnSynth
    {
        public static const RATE:int = 22050;
        // One cycle of a note, sampled. Linear interpolation between neighbours at
        // 22.05 kHz is inaudible at these frequencies and costs one multiply, which
        // is what makes a 40-second pass a few milliseconds instead of a second.
        private static const TBL:int = 2048;
        // The note table's time unit: hymn-data.cjs writes centiseconds.
        private static const UNIT:Number = 0.01;
        // Envelope, seconds: an organ speaks fast, a flute not quite as fast.
        private static const ATK_ORGAN:Number = 0.008;
        private static const ATK_FLUTE:Number = 0.03;
        private static const REL:Number = 0.07;

        // Render one pass of `seconds` seconds.
        //
        // `voices` is the four note strings from HymnNotes ("start,dur,key;..."), an
        // empty string for a part the tune does not have; `mask` says which parts are
        // audible (the S/A/T/B toggles). Returns a ByteArray of float32 samples plus
        // the numbers the beacon reports, so a silent result can be told from a quiet
        // one without listening.
        public static function render(voices:Array, mask:Array, instrument:String, seconds:Number):Object
        {
            var t0:int = getTimer();
            var frames:int = Math.round(seconds * RATE);
            if (frames < 1) frames = 1;

            // The mix bus. A Vector.<Number> is a plain double array in the generated
            // C, so indexing it in the inner loop is a load/store rather than a boxed
            // Array access; that is the whole reason this is 5 ms and not 500.
            var bus:Vector.<Number> = new Vector.<Number>();
            for (var i:int = 0; i < frames; i++) bus.push(0);

            var amps:Array = amplitudes(instrument);
            var gains:Array = [1.0, 0.92, 0.88, 0.95];   // S A T B
            var tables:Object = {};
            var notes:int = 0;
            for (var v:int = 0; v < 4; v++)
            {
                if (mask[v] != true) continue;
                var text:String = String(voices[v]);
                if (text == null || text == "") continue;
                notes += mixVoice(bus, frames, text, amps, tables, gains[v], instrument);
            }

            // Normalise: the toggles change how many parts are sounding, and a hymn
            // must not get quieter when a part is muted. Peak 0.85 leaves the mixer
            // headroom so the device's own volume, not our clipping, sets the level.
            var peak:Number = 0;
            for (i = 0; i < frames; i++)
            {
                var a:Number = bus[i];
                if (a < 0) a = -a;
                if (a > peak) peak = a;
            }
            var scale:Number = peak > 0.0001 ? 0.85 / peak : 0;

            var out:ByteArray = new ByteArray();
            out.endian = "littleEndian";
            for (i = 0; i < frames; i++) out.writeFloat(bus[i] * scale);

            return {
                pcm: out,
                samples: frames,
                peak: peak,
                notes: notes,
                ms: getTimer() - t0
            };
        }

        // Add one part to the bus. Returns how many notes it played.
        private static function mixVoice(bus:Vector.<Number>, frames:int, text:String,
            amps:Array, tables:Object, gain:Number, instrument:String):int
        {
            var atk:int = int((instrument == "Flute" ? ATK_FLUTE : ATK_ORGAN) * RATE);
            var rel:int = int(REL * RATE);
            var rows:Array = text.split(";");
            var played:int = 0;
            for (var r:int = 0; r < rows.length; r++)
            {
                var parts:Array = String(rows[r]).split(",");
                if (parts.length < 3) continue;
                var start:int = int(int(parts[0]) * UNIT * RATE);
                var dur:int = int(int(parts[1]) * UNIT * RATE);
                var key:int = int(parts[2]);
                if (start >= frames) continue;
                var len:int = dur;
                if (start + len > frames) len = frames - start;
                if (len < 1) continue;

                var wave:Vector.<Number> = table(tables, amps, key);
                var freq:Number = 440 * Math.pow(2, (key - 69) / 12);
                var step:Number = freq / RATE * TBL;
                var phase:Number = 0;

                for (var i:int = 0; i < len; i++)
                {
                    var env:Number = 1;
                    if (i < atk) env = i / atk;
                    var tail:int = len - i;
                    if (tail < rel) env = tail / rel;
                    var idx:int = int(phase);
                    var fr:Number = phase - idx;
                    var n1:int = idx + 1;
                    if (n1 >= TBL) n1 = 0;
                    var s0:Number = wave[idx];
                    bus[start + i] += (s0 + (wave[n1] - s0) * fr) * env * gain;
                    phase += step;
                    if (phase >= TBL) phase -= TBL;
                }
                played++;
            }
            return played;
        }

        // One cycle of the instrument's timbre at `key`'s fundamental. Cached per key:
        // a part repeats pitches constantly and building the table is 2048 sines.
        private static function table(tables:Object, amps:Array, key:int):Vector.<Number>
        {
            var k:String = "k" + String(key);
            var hit:Vector.<Number> = tables[k] as Vector.<Number>;
            if (hit != null) return hit;
            var t:Vector.<Number> = new Vector.<Number>();
            for (var i:int = 0; i < TBL; i++)
            {
                var ph:Number = i * 6.283185307179586 / TBL;
                var v:Number = 0;
                for (var h:int = 0; h < amps.length; h++) v += amps[h] * Math.sin(ph * (h + 1));
                t.push(v);
            }
            tables[k] = t;
            return t;
        }

        // GM 19 "Church Organ" as four drawbars (8', 4', 2 2/3', 2'), and GM 73
        // "Flute" as a fundamental with a little of the second partial that makes a
        // sine sound blown rather than generated.
        private static function amplitudes(instrument:String):Array
        {
            return instrument == "Flute" ? [1, 0.12] : [1, 0.55, 0.35, 0.28];
        }

        // Parse one voice string into [startFrames, durFrames, key] triples. Kept
        // separate from render() so the beacon can count what a part actually holds.
        public static function parse(text:String):Array
        {
            var out:Array = [];
            if (text == null || text == "") return out;
            var rows:Array = text.split(";");
            for (var i:int = 0; i < rows.length; i++)
            {
                var p:Array = String(rows[i]).split(",");
                if (p.length < 3) continue;
                out.push([int(int(p[0]) * UNIT * RATE), int(int(p[1]) * UNIT * RATE), int(p[2])]);
            }
            return out;
        }
    }
}
