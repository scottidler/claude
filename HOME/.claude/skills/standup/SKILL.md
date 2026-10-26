---
name: standup
description: Open a standup Google Meet in a new Firefox window. Use when the user types /standup or says "standup SRE", "standup SEC", or "standup DP".
allowed-tools: Bash(firefox:*)
---

# Standup

Open the Meet link for a team standup in a new Firefox window.

## Usage

`/standup <team>` where `<team>` is `SRE`, `SEC`, or `DP` (case-insensitive).

| Team | Meeting | URL |
|------|---------|-----|
| SRE | SRE Parking Lot | https://meet.google.com/enp-ecdj-vww |
| SEC | SEC Standup | https://meet.google.com/xgy-edpp-xju |
| DP | Data Platform \| Standup / SoS prep | https://meet.google.com/wxj-msgj-uxg |

## Steps

1. Match the argument to a row above. If it is missing or unknown, ask which of SRE, SEC, or DP.
2. Run `firefox --new-window <url>`.
3. Reply with one line: the team and the URL.
