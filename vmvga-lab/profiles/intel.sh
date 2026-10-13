#!/usr/bin/env bash
# Rendererprofile – Sourcen (set -a Effekt durch export). Nutzung in start-Skripten.
# Intel(R) Graphics (RPL-S) = ANV, Vulkan 1.4 – erster Kandidat laut Auftrag.
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/intel_icd.x86_64.json
export DXVK_FILTER_DEVICE_NAME="Intel"
export MESA_VK_DEVICE_SELECT=force
export DXVK_HUD=0
