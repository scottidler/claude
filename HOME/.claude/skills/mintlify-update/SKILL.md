---
name: mintlify-update
description: Download and install the latest Mintlify desktop app on this Linux machine, and relaunch it if it was running. Use whenever Scott says Mintlify shows "Update available", asks to update, upgrade, or install the latest Mintlify, or pastes a screenshot of the Mintlify "Update available" badge, even if he never says "skill" or names the update script.
---

# mintlify-update

Mintlify Desktop on this machine is a self-managed AppImage, extracted under `~/.local/share/mintlify-desktop/app-<version>/squashfs-root`. The app's own "Update available" button does not work here, so the update is a script.

## Run it

```bash
bash ~/.claude/skills/mintlify-update/scripts/update-and-restart.sh
```

The script does four things in order:

1. Records whether Mintlify is running (the main Electron process, not its `--type=` helpers).
2. If running, quits it with SIGTERM and waits up to 15 seconds. It never uses SIGKILL, because that can lose an unsaved edit.
3. Calls `~/.local/bin/mintlify-update` (dotfiles-managed). That script polls `https://desktop.mintlify.com/update/linux/x64`, downloads the AppImage, extracts it, repoints the `.desktop` file and the `~/.local/bin/mintlify-desktop` symlink. It refuses to run while the app is up, which is why step 2 exists.
4. If the app was running at step 1, relaunches the new version detached from the shell. If it was not running, it does not launch it.

## Report

- Old version -> new version, or "already latest".
- Whether the app was restarted.
- Proof: `pgrep -af 'app-<new>/squashfs-root/mintlify-desktop'` output, or "was not running, not launched".

## If it fails

- Quit timeout: the script exits non-zero and leaves the app alone. Tell Scott; do not force-kill.
- Download or extract failure: the old `app-<old>` directory is untouched and still works. Relaunch it if the script quit it.
- Update logic changes (feed URL, layout) belong in `~/repos/scottidler/dotfiles/HOME/.local/bin/mintlify-update`, not here.
