---
name: audio-reset
description: >
  Reset the PipeWire audio stack after meetily (or another app) corrupts it, without a reboot or
  relogin. Fire when the user reports pops, clicks, skips, or stutter on sustained audio, says
  meetily messed up the sound, or asks to "reset the audio" or "fix the sound". Kills meetily,
  restarts pipewire, pipewire-pulse and wireplumber, then verifies no process holds the ALSA
  devices and the kernel log is quiet. Covers the Sound Blaster X4 USB fallback.
---

# audio-reset

Root cause seen 2026-10-27 to 2026-11-03 (clyde sessions `479243f7`, `b926d3f7`): `meetily` opens
`/dev/snd/pcm*` devices directly, bypassing PipeWire. The Sound Blaster X4 USB device then logs
`Incompatible EP setup` and `current rate` errors, and sustained playback pops. A reboot clears it. This
reset does too.

## Steps

0. Check what the reset will break. Stop and ask the user if any of these is true:
   - `pgrep -a meetily` shows a process. A `meetily` process can outlive its closed window and keep
     recording. Check `find ~/Documents/meetily-recordings -type f -mmin -3` for fresh chunks. `pkill`
     leaves a session with no merged `audio.mp4` (2026-11-13: 17.5 hours, 1.3G).
   - A call is open or about to start (Meet tab, Zoom). The restart drops the mic until Firefox is killed.
   Never trust "I closed it" over `pgrep`.
1. Confirm the cause. Run both and read the output:
   - `fuser -v /dev/snd/pcm*` (does `meetily` hold a device?)
   - `journalctl -k --since "-1min" | grep -E 'current rate|EP setup'` (kernel errors)
2. Kill `meetily` first. If it stays alive, it grabs the devices again as PipeWire restarts.
   - `pkill meetily`
3. Restart the stack.
   - `systemctl --user restart pipewire pipewire-pulse wireplumber`
4. Verify, and report the output of each:
   - `systemctl --user is-active pipewire pipewire-pulse wireplumber` (all `active`)
   - `fuser -v /dev/snd/pcm*` (no holders)
   - `journalctl -k --since "-10sec" | grep -c 'current rate'` (0)
   - `wpctl status` (default sink is the Sound Blaster X4, streams listed)
5. Tell the user the pops are not verified until they play sustained audio.

## After the restart

- Firefox may not reconnect. On 2026-11-13 a Google Meet tab showed "Microphone not found" while
  `pactl get-default-source` listed the mic. Reloading the tab did not help. Only a full Firefox kill did.
  Tell the user this before the restart, never after.
- Zoom reconnected on 2026-10-29. Not verified since.
- Spotify does not. Ask the user to pause then play. If silent, Spotify needs a full restart.
  Do not kill it unasked: that ends their playback session.
- Do not restart `meetily` unasked. It triggers the problem again.

## If pops persist

The X4 may be stuck after the `Incompatible EP setup` error. Unplug and replug it, or run
`usbreset` on its bus id (it was `3-1`; confirm with `lsusb`). Ask before running `usbreset`: it drops the device.

## Permanent fix (not done)

A PipeWire-only rule for `meetily`: force its audio input and output through the PipeWire or
PulseAudio device so it never opens ALSA directly. The session read the `meetily` source for a
patch but no patch is recorded. Check `b926d3f7` before claiming one exists.
