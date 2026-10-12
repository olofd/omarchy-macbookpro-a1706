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

**Limits (from the driver's own notes):** the microphone records very quietly, the sound does not match macOS's
DSP, and `hw:0,0` devices have no volume control, so use PipeWire, not raw ALSA devices.
