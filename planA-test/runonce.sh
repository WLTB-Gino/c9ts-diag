#!/bin/sh
# runonce.sh — PLAN-A TEST: stock Jooan sensor_cv2005.ko + stock IQ (v1)
# Swaps the profile's sc2336p module for the byte-verified STOCK cv2005
# driver recovered from the W8-U donor flash (sha256 e5080976…f310ca),
# stages the stock IQ file, restarts the streamer, captures evidence.
#
# READ-MOSTLY: writes only /etc/sensor/cv2005.bin (remove to undo) and
# log/snapshot files on the SD card. A power-cycle restores the stock
# module state automatically (boot always loads the profile's sc2336p).
#
# Output on card: planA-test.log, planA-snap.jpg (if snapshot works)
#
# BEFORE INSERTING CARD: delete any runonce.done from the card root.

MMC=$(ls -d /mnt/mmc* 2>/dev/null | head -1)
[ -z "$MMC" ] && MMC=/tmp
SRC=$MMC/planA-test
LOG=$MMC/planA-test.log

log() { echo "[$(date '+%H:%M:%S')] $*" >>"$LOG" 2>&1; }
run() { echo "\$ $*" >>"$LOG" 2>&1; "$@" >>"$LOG" 2>&1; }
: > "$LOG"
log "=== PLAN-A: stock cv2005 module + IQ test start ==="

# 0. package sanity (hash must match the donor-extracted stock module)
run sha256sum $SRC/sensor_cv2005.ko $SRC/cv2005-t23.bin
run ls -la $SRC

# 1. record initial state
run lsmod
log "--- /etc/sensor/ contents (IQ path convention check) ---"
run ls -la /etc/sensor/

# 2. stop the streamer (whatever occupies S31)
log "--- stopping streamer ---"
for s in /etc/init.d/S31*; do
	[ -x "$s" ] || continue
	log "stop $(basename $s)"
	"$s" stop >>"$LOG" 2>&1
done
sleep 2

# 3. stage stock IQ FIRST (the ISP reads it when the new sensor registers)
#    (backup anything already at the target path)
if [ -f /etc/sensor/cv2005.bin ]; then
	cp /etc/sensor/cv2005.bin /etc/sensor/cv2005.bin.planA-backup
	log "backed up existing /etc/sensor/cv2005.bin"
fi
cp $SRC/cv2005-t23.bin /etc/sensor/cv2005.bin
log "staged stock IQ as /etc/sensor/cv2005.bin (before insmod)"

# 4. swap sensor modules: out with sc2336p (wrong sensor) and any prior
#    cv2005 build, in with the stock module (registers as sensor_cv2005_t23)
run rmmod sensor_sc2336p_t23
run rmmod sensor_cv2005_t23
sleep 1
cp $SRC/sensor_cv2005.ko /tmp/sensor_cv2005.ko
run insmod /tmp/sensor_cv2005.ko
sleep 2
log "--- dmesg after stock insmod (want: probe ok ------->cv2005) ---"
run dmesg | tail -12
run lsmod

# 5. restart the streamer against the new module
log "--- starting streamer ---"
for s in /etc/init.d/S31*; do
	[ -x "$s" ] || continue
	log "start $(basename $s)"
	"$s" start >>"$LOG" 2>&1
done

# 6. settle, then collect evidence
sleep 15
log "=== evidence: dmesg (full tail) ==="
run dmesg | tail -40
log "=== evidence: logread tail ==="
run logread | tail -20
log "=== evidence: frame-wait signatures ==="
run dmesg | grep -i 'frame\|cv2005\|mipi\|isp' | tail -20

# 7. attempt local snapshot (endpoint may vary; size check tells us if real)
wget -q -O $MMC/planA-snap.jpg http://127.0.0.1/image.jpg 2>/dev/null
if [ -s $MMC/planA-snap.jpg ]; then
	SZ=$(wc -c < $MMC/planA-snap.jpg)
	log "snapshot saved: planA-snap.jpg ($SZ bytes) — >10KB likely a real frame"
	[ "$SZ" -lt 10240 ] && rm -f $MMC/planA-snap.jpg && log "snapshot too small — removed; use the web UI instead"
else
	log "no snapshot from /image.jpg — check live view in the web UI instead"
fi

log "=== PLAN-A test end — NOW LOOK AT THE WEB UI LIVE VIEW ==="
log "non-black picture  = stock driver works, our port gets fixed from its tables"
log "still black        = stock is black too — hardware/ISP-level issue"
log "undo: power-cycle (module) + rm /etc/sensor/cv2005.bin (if no .planA-backup exists)"
sync
exit 0
