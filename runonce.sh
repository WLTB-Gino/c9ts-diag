#!/bin/sh
# runonce.sh — C9TS station-association diagnostic (v3)
# Read-only w.r.t. stored config: uses your existing /etc/wpa_supplicant.conf
# and restores the camera's boot network state (incl. portal/AP mode) at exit.
# Output: /mnt/mmc/c9ts-diag.log on the SD card.

# Auto-detect SD mount point (mmc vs mmc0 depending on SoC slot count)
MMC=$(ls -d /mnt/mmc* 2>/dev/null | head -1)
[ -z "$MMC" ] && MMC=/tmp

LOG=$MMC/c9ts-diag.log
IF=wlan0
CONF=/etc/wpa_supplicant.conf
STOCK_PID=/run/wpa_supplicant.$IF.pid
DIAG_PID=/run/wpa_supplicant.diag.pid
CLI="wpa_cli -i $IF"

log() { echo "[diag $(date '+%H:%M:%S')] $*" >>"$LOG" 2>&1; }
run() { echo "\$ $*" >>"$LOG" 2>&1; "$@" >>"$LOG" 2>&1; }
: > "$LOG"
log "=== station-assoc diagnostic start ==="

run lsmod
run ip link show $IF

# Temporarily stop the stock supplicant so we can watch this interface
# with per-state polling; restored to boot behaviour at the end.
WAS_RUNNING=0
if [ -s "$STOCK_PID" ] && kill -0 "$(cat $STOCK_PID)" 2>/dev/null; then
	WAS_RUNNING=1
	log "stopping stock wpa_supplicant (will restore after test)"
	kill "$(cat $STOCK_PID)" 2>/dev/null
	sleep 2
fi

[ -s "$DIAG_PID" ] && kill "$(cat $DIAG_PID)" 2>/dev/null
wpa_supplicant -i $IF -c "$CONF" -P "$DIAG_PID" -B >>"$LOG" 2>&1
sleep 3

run $CLI status
run $CLI scan
sleep 3
run $CLI scan_results

log "--- reassociate; polling state for up to 30s ---"
run $CLI reassociate
STATE=unknown
n=0
while [ $n -lt 10 ]; do
	sleep 3
	STATE=$($CLI status 2>/dev/null | sed -n 's/^wpa_state=//p')
	log "t=$(( (n + 1) * 3 ))s state=$STATE"
	case "$STATE" in
		COMPLETED|4WAY_HANDSHAKE|GROUP_HANDSHAKE|ASSOCIATED) break ;;
	esac
	n=$((n + 1))
done
run $CLI status

case "$STATE" in
	COMPLETED)
		log "RESULT: ASSOCIATED+4WAY-OK (station path healthy; fault is AP-mode side)" ;;
	4WAY_HANDSHAKE|GROUP_HANDSHAKE|ASSOCIATED)
		log "RESULT: ASSOC-OK-4WAY-STUCK (AP answers; WPA handshake stalls)" ;;
	ASSOCIATING|AUTHENTICATING)
		log "RESULT: ASSOC-NO-REPLY (AP never answers association)" ;;
	*)
		log "RESULT: state=$STATE (SCANNING/DISCONNECTED => your AP not seen or assoc rejected; check scan_results above)" ;;
esac

log "--- DHCP attempt ---"
run udhcpc -i $IF -n -q -t 4
run ip addr show $IF

log "--- restoring boot state ---"
[ -s "$DIAG_PID" ] && kill "$(cat $DIAG_PID)" 2>/dev/null
sleep 2
if [ "$WAS_RUNNING" = 1 ]; then
	/etc/init.d/S38wpa_supplicant start >>"$LOG" 2>&1
	log "stock wpa_supplicant restarted (boot behaviour restored)"
else
	log "stock supplicant was not running; leaving network stack as found"
fi
log "=== diagnostic end ==="

# Chain the sensor probe on the same boot (no second power cycle needed)
if [ -f "$MMC/sensor-probe.sh" ]; then
	log "--- chaining sensor-probe.sh ---"
	sh "$MMC/sensor-probe.sh"
fi
