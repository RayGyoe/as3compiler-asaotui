// HymnAudio: the tune on the sound card, driven by the model's own clock.
//
// WHAT THIS IS. `flash.media` in this runtime is a real implementation (miniaudio in
// vendor/audio_glue.c: WASAPI/DirectSound/WinMM on Windows), and
// `Sound.loadPCMFromByteArray` takes float32 mono PCM. So the app synthesises ONE
// pass of the selected tune (HymnSynth, ~15 ms for 37 s) and hands it to the device;
// everything above it -- the section map, the follow animation, "pause after each
// verse" -- keeps running on the frame clock it already had, and this class is only
// asked to start/stop at the right second.
//
// TWO HONEST LIMITS, both from the backend rather than from this file:
//
//   * A PCM image is program-lifetime (`as_audio_register_pcm` mallocs and never
//     frees; the table holds 64). So a render is spent only when the SOUND has to
//     change -- first play of a tune, a different hymn, an instrument or voice
//     toggle. Switching hymns in a session costs one image each, which is far below
//     the table, and `regs` reports the running count so a leak would be visible.
//   * With no backend (`ASC_HAVE_AUDIO` absent, or no device) `play()` returns null
//     and `Sound.length` is 0. That is reported, not hidden: `ready` goes false and
//     the player bar says there is no audio rather than showing a dead transport.
package hymn
{
    import flash.media.Sound;
    import flash.media.SoundChannel;
    import flash.media.SoundMixer;
    import flash.utils.getTimer;

    public final class HymnAudio
    {
        public var ready:Boolean = false;   // a real device answered play()
        public var ok:Boolean = false;      // the current hymn has a live PCM image
        public var renderMs:int = 0;        // cost of the last HymnSynth.render
        public var peak:Number = 0;         // pre-normalisation peak (0 = silence)
        public var samples:int = 0;         // frames in one pass
        public var regs:int = 0;            // PCM images registered this process
        public var status:String = "idle";  // what the player bar can print

        private var sound:Sound = null;
        private var chan:SoundChannel = null;
        private var imageKey:String = "";   // hymn|mask|instrument of the live image
        // One below the runtime's 64-slot PCM table (compiler-gaps.md G46).
        private static const IMAGE_CAP:int = 56;
        private var voices:Array = null;    // the four note strings of the open tune
        private var lenSec:Number = 0;

        public function HymnAudio()
        {
            // areSoundsInaccessible() is the runtime's own answer: true when this
            // build links no backend. Ask once; a play() that returns null also
            // downgrades `ready`, because a device can disappear mid-session.
            this.ready = !SoundMixer.areSoundsInaccessible();
            this.status = this.ready ? "ready" : "no audio backend";
        }

        // Open a tune's note row ("<number>\t<v0>\t<v1>\t<v2>\t<v3>"). Does not render:
        // the image is built on the first play, with the mask/instrument in force then.
        public function open(row:String, seconds:Number):void
        {
            this.stop();
            this.sound = null;
            this.imageKey = "";
            this.ok = false;
            this.lenSec = seconds > 0 ? seconds : 0;
            this.peak = 0;
            this.samples = 0;
            this.voices = null;
            if (row == null) return;
            var parts:Array = row.split("\t");
            if (parts.length < 5) return;
            this.voices = [parts[1], parts[2], parts[3], parts[4]];
        }

        public function close():void
        {
            this.open(null, 0);
            this.status = this.ready ? "ready" : "no audio backend";
        }

        // Start (or restart) at `fromSec` with the given parts and instrument. The
        // image is re-rendered only when its key changed, so play/pause/resume on the
        // same state reuses what is already on the device side.
        // `Sound.play`'s startTime is in MILLISECONDS (the reference: "the initial
        // position in milliseconds"); passing seconds starts every resume at ~0, which
        // is invisible in a play-from-the-top demo and wrong the first time the reader
        // unmutes halfway through a verse.
        public function play(fromSec:Number, mask:Array, instrument:String):Boolean
        {
            if (!this.ensure(mask, instrument)) return false;
            var start:Number = fromSec;
            if (start < 0) start = 0;
            if (start > this.lenSec) start = this.lenSec;
            if (this.chan != null)
            {
                this.chan.stop();
                this.chan = null;
            }
            var ch:SoundChannel = this.sound.play(start * 1000, 0, null);
            if (ch == null)
            {
                this.ready = false;
                this.status = "no audio device";
                return false;
            }
            this.chan = ch;
            this.status = "playing " + (this.imageKey);
            return true;
        }

        public function stop():void
        {
            if (this.chan != null)
            {
                this.chan.stop();
                this.chan = null;
            }
            if (this.voices != null) this.status = "paused";
        }

        // Where the DEVICE is, in seconds. The model keeps its own clock (that one
        // drives the map and the follow animation); this is the number the beacon
        // compares against it, so "audio is really moving" is measured, not assumed.
        public function positionSec():Number
        {
            if (this.chan == null) return -1;
            return this.chan.position / 1000;
        }

        public function isPlaying():Boolean
        {
            return this.chan != null;
        }

        private function ensure(mask:Array, instrument:String):Boolean
        {
            if (this.voices == null || this.lenSec <= 0) return false;
            var k:String = this.keyOf(mask, instrument);
            if (k == this.imageKey && this.sound != null) return true;

            // The backend's PCM registry is 64 slots for the life of the process
            // (`g_bufs[64]` in vendor/audio_glue.c, malloc'd and never freed), and the
            // 65th registration throws #2068 with nothing an app can do about it. A
            // session that plays enough tunes or toggles parts enough times can reach
            // that, so this class stays one image below the wall and says so instead
            // of dying. It is a backend limit, not a mix decision: see compiler-gaps.md.
            if (this.regs >= IMAGE_CAP)
            {
                this.sound = null;
                this.imageKey = "";
                this.status = "audio images full (" + String(this.regs) + ")";
                return false;
            }

            var r:Object = HymnSynth.render(this.voices, mask, instrument, this.lenSec);
            this.samples = int(r.samples);
            this.peak = Number(r.peak);
            this.renderMs = int(r.ms);
            if (this.peak <= 0.0001)
            {
                // Every part muted: nothing to hand the device, and saying so beats
                // starting a silent voice that reports as playing.
                this.sound = null;
                this.imageKey = "";
                this.status = "all parts muted";
                return false;
            }
            var snd:Sound = new Sound();
            // loadPCMFromByteArray reads from the ByteArray's CURRENT position (the
            // reference spells that out), and ours is at the END after the write loop --
            // rewind, or the call reports #2084 for the bytes it cannot see.
            r.pcm.position = 0;
            snd.loadPCMFromByteArray(r.pcm, uint(r.samples), "float", false, HymnSynth.RATE);
            this.regs++;
            if (snd.length <= 0)
            {
                // No backend: the payload is accepted but there is nothing to play
                // (flash.media's documented no-device result).
                this.ready = false;
                this.status = "no audio backend";
                this.sound = null;
                this.imageKey = "";
                return false;
            }
            this.sound = snd;
            this.imageKey = k;
            this.ok = true;
            return true;
        }

        private function keyOf(mask:Array, instrument:String):String
        {
            var b:String = "";
            for (var i:int = 0; i < mask.length; i++) b += mask[i] ? "1" : "0";
            return b + "|" + instrument;
        }
    }
}
