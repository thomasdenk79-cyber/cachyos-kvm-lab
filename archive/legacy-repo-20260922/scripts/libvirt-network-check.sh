#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--help|--check|--apply|--verify]\n' "$0"
  printf 'Set LIBVIRT_VM_NAME to detect an existing bridged interface.\n'
}
mode="$1"
case "$mode" in
  --help) usage; exit 0 ;;
  --check|--apply|--verify) ;;
  *) usage >&2; exit 2 ;;
esac

command -v virsh >/dev/null 2>&1 || { printf 'virsh is required\n' >&2; exit 2; }
virsh_system=(sudo -n virsh -c qemu:///system)
uplink=$(ip route show default | awk 'NR==1 {print $5}')
[[ -n "$uplink" ]] || { printf 'No default network uplink detected\n' >&2; exit 1; }
network_mode=nat
if [[ -n "${LIBVIRT_VM_NAME:-}" ]]; then
  interface_type=$("${virsh_system[@]}" domiflist "$LIBVIRT_VM_NAME" 2>/dev/null \
    | awk 'NR > 2 && $1 !~ /^-+$/ && $2 != "" {print $2; exit}' || true)
  case "$interface_type" in
    bridge) network_mode=bridged ;;
    network) network_mode=nat ;;
    *) network_mode=unknown ;;
  esac
  printf 'vm=%s network_mode=%s\n' "$LIBVIRT_VM_NAME" "$network_mode"
fi
if [[ "$network_mode" == bridged ]]; then
  printf 'Existing bridged networking detected; no NAT or UFW forwarding changes needed.\n'
  exit 0
fi
if [[ "$network_mode" == unknown ]]; then
  printf 'Unable to determine network mode for VM: %s\n' "$LIBVIRT_VM_NAME" >&2
  exit 1
fi

if [[ "$mode" == "--check" || "$mode" == "--verify" ]]; then
  printf 'uplink=%s\n' "$uplink"
  "${virsh_system[@]}" net-info default
  if systemctl is-active --quiet libvirtd.socket; then
    printf 'libvirt_daemon=libvirtd.socket\n'
  else
    systemctl is-active virtnetworkd.socket virtstoraged.socket virtqemud.socket virtlogd.socket
    printf 'libvirt_daemon=modular-sockets\n'
  fi
  if systemctl is-active --quiet ufw; then
    sudo -n ufw status | grep -Fq "ALLOW FWD" || {
      printf 'UFW routed forwarding rules are missing for virbr0/%s\n' "$uplink" >&2
      exit 1
    }
    sudo -n ufw status | grep -Fq '67/udp on virbr0' || {
      printf 'UFW DHCP rule is missing: DHCP Discover uses source 0.0.0.0; allow UDP/67 on virbr0 without a source subnet\n' >&2
      printf 'Run: sudo ufw allow in on virbr0 to any port 67 proto udp\n' >&2
      exit 1
    }
    sudo -n ufw status | grep -Fq '53/udp on virbr0' || {
      printf 'UFW libvirt DNS rule is missing on virbr0\n' >&2
      exit 1
    }
  fi
fi

if [[ "$mode" == "--verify" && -n "${LIBVIRT_VM_NAME:-}" ]]; then
  vm_mac=$("${virsh_system[@]}" domiflist "$LIBVIRT_VM_NAME" \
    | awk 'NR > 2 && $1 !~ /^-+$/ && $5 != "" {print $5; exit}')
  dhcp_leases=$("${virsh_system[@]}" net-dhcp-leases default)
  if [[ -n "$vm_mac" ]] && ! grep -qi "$vm_mac" <<< "$dhcp_leases"; then
    printf 'DHCP lease missing for %s (%s); diagnose host virbr0/UFW before changing the guest\n' \
      "$LIBVIRT_VM_NAME" "$vm_mac" >&2
    printf "Diagnostic: sudo tcpdump -ni virbr0 'arp or (udp port 67 or 68)'\n" >&2
    exit 1
  fi
fi

if [[ "$mode" == "--apply" ]]; then
  if ! sudo -n true; then
    sudo -v || { printf 'Initial sudo authentication failed\n' >&2; exit 1; }
  fi
  sudo -n true || { printf 'sudo authentication is unavailable\n' >&2; exit 1; }
  if systemctl is-active --quiet libvirtd.socket; then
    sudo -n systemctl enable libvirtd.socket
  else
    sudo -n systemctl enable --now virtnetworkd.socket virtstoraged.socket virtqemud.socket virtlogd.socket
  fi
  sudo -n systemctl enable --now virtlogd.socket
  "${virsh_system[@]}" net-start default 2>/dev/null || true
  "${virsh_system[@]}" net-autostart default
  if systemctl is-active --quiet ufw; then
    sudo -n ufw allow in on virbr0 from 192.168.122.0/24 to any port 53 proto udp
    sudo -n ufw allow in on virbr0 from 192.168.122.0/24 to any port 53 proto tcp
    # DHCP Discover starts with source 0.0.0.0, so do not restrict port 67 by guest subnet.
    sudo -n ufw allow in on virbr0 to any port 67 proto udp
    sudo -n ufw route allow in on virbr0 out on "$uplink"
    sudo -n ufw route allow in on "$uplink" out on virbr0
    sudo -n ufw reload
  fi
  printf 'libvirt NAT forwarding configured for virbr0 -> %s\n' "$uplink"
fi

if [[ "$mode" == "--apply" || "$mode" == "--verify" ]]; then
  "$0" --check
fi
