#!/usr/bin/env bash
# Profil 2: NVIDIA RTX 3500 Ada (hostseitiger Dienstbetrieb bleibt unberuehrt,
# nur DIESE QEMU-Instanz sieht nur die Ada). Blackwell ist hier bewusst gesperrt.
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
export DXVK_FILTER_DEVICE_NAME="RTX 3500 Ada"
export NVIDIA_VISIBLE_DEVICES=0000:01:00.0
export DXVK_HUD=0
