# RFSPager.app Agent

Receive and decode pager messages for NSW Rural Fire Service (RFS) and Fire and Rescue NSW (FRNSW) using a Raspberry Pi and RTL-SDR dongle(s).

## Requirements

Before you begin, make sure you have:

| Requirement | Details |
|-------------|---------|
| **Raspberry Pi** | Pi 3, 4, or 5 recommended |
| **Operating System** | Raspberry Pi OS, Ubuntu, or Debian |
| **RTL-SDR Dongle(s)** | 1 dongle = one service, 2 dongles = both services |
| **API Key** | Contact Nick to get your API key |
| **Site Name** | Contact Nick to get your assigned site name |

### Recommended Hardware

**Raspberry Pi 5:**
- [Raspberry Pi 5 (8GB)](https://core-electronics.com.au/raspberry-pi-5-model-b-8gb.html) - Core Electronics
- [Raspberry Pi 5 (16GB)](https://core-electronics.com.au/raspberry-pi-5-model-b-16gb.html) - Core Electronics

**RTL-SDR Dongle:**
- [NooElec NESDR SMArt Bundle](https://www.amazon.com.au/NooElec-NESDR-SMArt-Bundle-R820T2-Based/dp/B01GDN1T4S/) - Amazon AU

> **Note:** You'll need one RTL-SDR dongle per service. To monitor both RFS and FRNSW simultaneously, purchase two dongles.

### Service Frequencies

| Service | Frequency |
|---------|-----------|
| RFS (NSW Rural Fire Service) | 148.5875 MHz |
| FRNSW (Fire and Rescue NSW) | 148.9625 MHz |

## Installation

Run the following command as root:
```bash
curl -fsSL https://raw.githubusercontent.com/the-it-dept/rfspager-docs/main/agent.sh | sudo bash
```

The installer will:

1. Install RTL-SDR drivers and dependencies
2. Install Docker (if not already installed)
3. Detect your RTL-SDR dongle(s)
4. Prompt you for your API key and site name
5. Ask which service(s) to monitor (based on available dongles)
6. Configure and start the RFSPager agent

## Post-Installation

The agent is installed to `/opt/rfspager` and runs automatically via Docker.

### Useful Commands
```bash
# Navigate to install directory
cd /opt/rfspager

# View live logs
docker compose logs -f

# Check container status
docker compose ps

# Restart the agent
docker compose restart

# Stop the agent
docker compose down

# Update to latest version
docker compose pull && docker compose up -d
```

## Troubleshooting

### RTL-SDR not detected

If the installer doesn't detect your RTL-SDR dongle(s):

1. Ensure the dongle(s) are plugged in
2. Reboot the Pi (required after first install to load the driver blacklist)
3. Run `rtl_test` to verify detection
```bash
rtl_test
```

You should see output like:
```
Found 2 device(s):
  0:  Realtek, RTL2838UHIDIR, SN: RFS00001
  1:  Realtek, RTL2838UHIDIR, SN: RFS00006
```

### Check container logs

If the agent isn't working correctly, check the logs:
```bash
cd /opt/rfspager
docker compose logs -f
```

## Support

For API keys, site names, or support, contact **Nick**.

## Contributing

RFSPager.app relies on volunteers running agents across NSW. Thank you for contributing to the network!