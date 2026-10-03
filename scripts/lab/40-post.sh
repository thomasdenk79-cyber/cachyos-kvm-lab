#!/usr/bin/env bash
# 40-post.sh <vm> <timeout_min> - wartet auf qemu-agent + Post-Flag und prueft Dienste.
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh
VM=${1:?}; TMO=${2:-45}
deadline=$(( $(date +%s) + TMO*60 ))

qga() { sudo virsh -c qemu:///system qemu-agent-command "$VM" "$1" 2>/dev/null; }
until qga '{"execute":"guest-ping"}' | grep -q '"return"'; do
  [ $(date +%s) -lt $deadline ] || { echo "$VM: qemu-agent nicht erreichbar"; exit 1; }
  state=$(sudo virsh -c qemu:///system domstate $VM 2>/dev/null || echo "?")
  echo "warte auf agent ($state)..."
  sleep 10
done
echo "$VM: qemu-agent OK"

SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 ${VM_USER}@$(vm_ip $VM)"

if [ "$VM" = "vm-win11" ]; then
  while :; do
    r=$(qga '{"execute":"guest-exec","arguments":{"path":"cmd.exe","arg":["/c","if exist C:\\Lab\\done echo LABDONE"],"capture-output":true}}' || true)
    pid=$(echo "$r" | grep -o '"pid": *[0-9]*' | grep -o '[0-9]*')
    if [ -n "${pid:-}" ]; then
      sleep 3
      out=$(qga "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$pid}}" || true)
      echo "$out" | grep -q LABDONE && { echo "$VM: Post-Flag ok"; break; }
    fi
    [ $(date +%s) -lt $deadline ] || { echo "$VM: Post nicht fertig"; exit 1; }
    echo "win-post laeuft noch..."; sleep 60
  done
  RDP=$(qga '{"execute":"guest-exec","arguments":{"path":"cmd.exe","arg":["/c","sc query TermService"],"capture-output":true}}' | grep -o '"pid": *[0-9]*' | grep -o '[0-9]*')
  sleep 2; qga "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$RDP}}" | grep -qiE "RUNNING|erfolgreich|BASE" && echo "$VM: RDP-Service laeuft"
  nc -z -w3 $(vm_ip $VM) 3389 && echo "$VM: TCP 3389 offen"
  nc -z -w3 $(vm_ip $VM) 22 && echo "$VM: TCP 22 offen"
else
  while :; do
    if $SSH "test -f /var/lib/lab-postdone" 2>/dev/null; then echo "$VM: Post-Flag ok"; break; fi
    [ $(date +%s) -lt $deadline ] || { echo "$VM: Post nicht fertig"; exit 1; }
    echo "warte auf $VM Post..."; sleep 60
  done
  $SSH "systemctl is-active qemu-agent ssh xrdp | tr '\n' ' '; echo; hostnamectl | grep Static" 
fi
echo "$VM: PRUEFKOMPLETT"
