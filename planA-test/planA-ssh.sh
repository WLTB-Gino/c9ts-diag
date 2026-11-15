#!/bin/sh
# planA-ssh.sh — PLAN-A ground-truth test over SSH (no SD card needed)
# Payload must already be in /tmp (scp'd from your PC):
#   sensor_cv2005.ko  (stock driver, sha256 e5080976…f310ca)
#   cv2005-t23.bin    (stock IQ,     sha256 1081b40d…ad4f4)
#
# Does exactly what the SD-card runonce.sh does: hash-gates the payload,
# stops the streamer, stages the stock IQ BEFORE insmod, swaps the
# sc2336p module for the stock cv2005 driver, restarts the streamer,
# captures evidence to /tmp/planA-ssh.log and prints it at the end.
#
# Run:   sh /tmp/planA-ssh.sh        (~30s)
# Undo:  power-cycle (profile module reloads) and optionally
#        rm /etc/sensor/cv2005.bin  (a .planA-backup is kept if one existed)

L=/tmp/planA-ssh.log
K=/tmp/sensor_cv2005.ko
Q=/tmp/cv2005-t23.bin

log() { echo "[$(date '+%H:%M:%S')] $*" >>"$L"; }
run() { echo "\$ $*" >>"$L"; "$@" >>"$L" 2>&1; }

: >"$L"
log "=== PLAN-A SSH start ==="

# 0. payload present?
[ -s "$K" ] || { log "ABORT: $K missing (scp it to /tmp first)"; cat "$L"; exit 1; }
[ -s "$Q" ] || { log "ABORT: $Q missing (scp it to /tmp first)"; cat "$L"; exit 1; }

# 1. hash gate — abort on any mismatch
KH=$(sha256sum "$K" | cut -d' ' -f1)
QH=$(sha256sum "$Q" | cut -d' ' -f1)
log "ko sha256: $KH"
log "iq sha256: $QH"
[ "$KH" = "e5080976a0f9d45e6621746a325fa26e13783ecb558d10d160c7848157f310ca" ] || { log "ABORT: module hash mismatch"; cat "$L"; exit 1; }
[ "$QH" = "1081b40d0179695f8ee597213333eb99aab4f895b529c7d3f1aa1d1acf7ad4f4" ] || { log "ABORT: IQ hash mismatch"; cat "$L"; exit 1; }

# 2. record initial state
log "--- initial state ---"
run lsmod
run ls -la /etc/sensor/

# 3. stop the streamer
log "--- stopping streamer ---"
for s in /etc/init.d/S31*; do
	[ -x "$s" ] || continue
	log "stop $(basename "$s")"
	"$s" stop >>"$L" 2>&1
done
sleep 2

# 4. stage stock IQ FIRST (ISP reads it when the sensor module registers)
if [ -f /etc/sensor/cv2005.bin ]; then
	cp /etc/sensor/cv2005.bin /etc/sensor/cv2005.bin.planA-backup
	log "backed up existing /etc/sensor/cv2005.bin"
fi
cp "$Q" /etc/sensor/cv2005.bin
log "stock IQ staged BEFORE insmod"

# 5. swap modules: out with sc2336p (wrong sensor), in with stock driver
run rmmod sensor_sc2336p_t23
run rmmod sensor_cv2005_t23
sleep 1
run insmod "$K"
sleep 2
log "--- dmesg after insmod (want: probe ok ------->cv2005) ---"
run dmesg | tail -12
run lsmod

# 6. restart the streamer against the new module
log "--- starting streamer ---"
for s in /etc/init.d/S31*; do
	[ -x "$s" ] || continue
	log "start $(basename "$s")"
	"$s" start >>"$L" 2>&1
done

# 7. settle, then collect evidence
sleep 15
log "=== evidence: dmesg tail ==="
run dmesg | tail -40
log "=== probe: sensor answer (plan-A verdict lines, before truncation) ==="
run dmesg | grep -i 'cv2005\|probe ok\|chip found\|i2c\|sensor' | tail -25
run cat /proc/jz/isp/isp-m0
run cat /proc/jz/sensor/info 2>/dev/null
log "=== evidence: logread tail ==="
run logread | tail -20
log "=== evidence: frame/sensor signatures ==="
run dmesg | grep -i 'frame\|cv2005\|mipi\|isp' | tail -20

# 8. snapshot attempt (size check tells us if it is a real frame)
# HARDENED: never call wget unbounded (busybox wget may have no timeout
# support — this exact call wedged a C9TS boot on 2026-11-15 when the
# streamer was down). Port check first, hard timeout always.
if netstat -tln 2>/dev/null | grep -q ':80 '; then
	timeout 8 wget -q -O /tmp/planA-snap.jpg http://127.0.0.1/image.jpg 2>/dev/null
	[ -s /tmp/planA-snap.jpg ] && log "snapshot: $(wc -c < /tmp/planA-snap.jpg) bytes" \
		|| log "snapshot: no data (port open, no frame or wget/timeout missing)"
else
	log "snapshot: skipped (streamer HTTP port not listening — streamer did not come up)"
fi

log "=== end — NOW CHECK THE WEB UI LIVE VIEW ==="
log "picture     = stock works, port gets fixed from its tables"
log "still black = stock is black too, hardware/ISP-level issue"
echo ""
echo "===== paste ALL of this back to Gino ====="
cat "$L"
