#!/bin/bash
# Onboard-MDE-Linux.sh  -  run ONCE on VM-EPH-LNX01, manually, after first login.
#
# MDE for Linux onboarding is tenant-specific and installed via the mdatp
# package plus a tenant onboarding blob you download from the Defender portal
# (Settings -> Endpoints -> Onboarding -> Linux Server). Follow Microsoft's
# current install instructions for your distro (Ubuntu 22.04 here); this
# script assumes you've already added the Microsoft package repo per those
# docs and have the onboarding package downloaded to the VM.
#
# Usage: ./Onboard-MDE-Linux.sh /path/to/MicrosoftDefenderATPOnboardingLinuxServer.py

set -euo pipefail

ONBOARDING_SCRIPT="${1:?Usage: $0 /path/to/onboarding-script.py}"

if [ ! -f "$ONBOARDING_SCRIPT" ]; then
    echo "Onboarding script not found at $ONBOARDING_SCRIPT" >&2
    exit 1
fi

sudo apt-get update
sudo apt-get install -y mdatp
sudo python3 "$ONBOARDING_SCRIPT"

echo "Onboarding invoked. Check status with: mdatp health"
