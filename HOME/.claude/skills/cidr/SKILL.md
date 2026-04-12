---
name: cidr
description: CIDR calculator for network calculations. Use when working with IP addresses, subnets, or network ranges.
allowed-tools: Bash(cidr:*)
---

# CIDR Calculator

`cidr` is a CLI tool for pretty-printing CIDR/subnet information with color-coded output and hex representations.

## Usage

```bash
cidr 10.10.10.1/16         # Show info for 10.10.10.1/16
cidr 192.168.1.0/24        # Show info for 192.168.1.0/24
cidr /24                   # Use default network (192.168.1.0) with /24
cidr /16 /24 /28           # Compare multiple prefix lengths
cidr 10.0.0.1 -m 255.255.248.0  # Use netmask instead of prefix
```

## Output Example

```
192.168.1.0/24:
    Network:  0xc0a80100  192.168.1.0
  Broadcast:  0xc0a801ff  192.168.1.255
    Netmask:  0xffffff00  255.255.255.0
 First Host:  0xc0a80101  192.168.1.1
  Last Host:  0xc0a801fe  192.168.1.254
  Addresses:  (254 usable)
```

## Features

- Color-coded output for easy reading
- Hex representations for each address
- Shows network, broadcast, netmask, first/last host
- Usable address count
- Supports multiple addresses in one command
- Environment variable `DEFAULT_NETWORK` for custom default

## Common Subnet Sizes

| Prefix | Hosts | Netmask |
|--------|-------|---------|
| /8 | 16M | 255.0.0.0 |
| /16 | 65,534 | 255.255.0.0 |
| /20 | 4,094 | 255.255.240.0 |
| /24 | 254 | 255.255.255.0 |
| /28 | 14 | 255.255.255.240 |
| /30 | 2 | 255.255.255.252 |
| /32 | 1 | 255.255.255.255 |

