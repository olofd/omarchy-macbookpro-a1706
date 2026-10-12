# 2. Sound

**Symptom:** `aplay -l` shows a card, PipeWire shows "Dummy Output" or the speakers are silent.

**Cause:** the A1706 uses a **Cirrus Logic CS8409** codec with external I2C speaker amplifiers. The in-kernel
`snd_hda_codec_cs8409` loads but does not initialise the amplifiers.

**Check:** `cat /proc/asound/card*/codec#* | grep Codec` lists `Cirrus Logic CS8409`.

**Fix:** the community driver
[davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro), built with DKMS so it follows
kernel updates:

```sh
sudo sh scripts/install-sound.sh
sudo reboot
```

What the script gets right, because the obvious way fails:

- It clones the driver to `/usr/local/src/snd_hda_macbookpro` and **leaves it there**. DKMS keeps a symlink to
  the source folder, so building from a temporary directory leaves the module "broken" (`dkms status` says
  "Missing the module source directory").
- It installs the kernel headers that match the running kernel (`linux-omarchy-headers` here).
- If the driver does not build (6.17 changed the sound source layout), it tries the
  [egorenar fork](https://github.com/egorenar/snd_hda_macbookpro). That choice is made when you run the
  script; DKMS then rebuilds whichever one was installed for each new kernel.

**After the reboot:** `aplay -l` shows `CS8409/CS42L83 Analog`, PipeWire lists "Built-in Audio Analog Stereo".
Turn the volume down before the first test: the speakers can be loud.

**Limits (from the driver's own notes):** the sound does not match macOS's DSP, and `hw:0,0` devices have no
volume control, so use PipeWire, not raw ALSA devices.

## The microphone (fixed with a driver patch)

**Symptom:** the built-in mic records quietly (speech peaking around -22 dBFS at a normal distance; -12 to -6
is right for calls and dictation), and the mic slider changes nothing.

**Cause:** the driver copies what OS X does: at boot and at **every capture start** it writes the mic's gain
(codec node `0x22`) straight to the codec, always `0x27`, which is -12 dB (`0x33` is 0 dB, `0x3f` +12 dB, 1 dB
steps). It bypasses the mixer, so `Internal Mic Capture Volume` showed +12 dB while the codec recorded at
-12 dB. Check it while recording: `awk '/^Node 0x22 /,/^Node 0x23 /' /proc/asound/card0/codec#0 | grep Amp-In`.

**Fix:**
[`snd-hda-macbookpro/0001-internal-mic-gain-from-mixer.patch`](../snd-hda-macbookpro/0001-internal-mic-gain-from-mixer.patch)
makes the driver take the gain from the mixer control instead. `install-sound.sh` applies it to the driver's
source (for a new install, and to a driver installed before), rebuilds it and records which patches the
installed module has, so DKMS's rebuilds for new kernels keep it. It also sets the mic's starting level to 85 %
(`files/wireplumber-internal-mic.conf`, only for this sound card). On a Mac set up before this fix, set the
level once (change to taste):

```sh
pactl set-source-volume alsa_input.pci-0000_00_1f.3.analog-stereo 85%
```

**Result.** The mic slider now changes the level: a test tone played by the speakers and recorded by the mic,
alternating the old and the new setting, came in 11 dB louder at 63 % (-52.8 vs -41.8 dBFS). Dictating at a
normal distance, speech peaked around -27 dBFS at 63 %, around -9 (highest -4, no clipping) at 100 %, and around
-13 to -8 at **85 %**, the right range for calls and dictation; the signal-to-noise ratio stays about 26 dB (the
mic is digital, so the gain in the codec adds no noise compared with software gain).

**A thump at every recording start** (up to -0.5 dBFS in the first half second, about -8 dBFS since the fix)
comes from the capture path powering up; it is not fixed yet. Tools that measure the level should skip the
first 0.6 s.
