#!/bin/sh
# sensor-probe.sh — C9TS sensor identification (v3, READ-ONLY)
# I2C reads only. No register writes, no stream-on commands.
# Runs automatically after runonce.sh on the same boot.
# Output: /mnt/mmc/sensor-id.txt on the SD card.

# Auto-detect SD mount point (mmc vs mmc0 depending on SoC slot count)
MMC=$(ls -d /mnt/mmc* 2>/dev/null | head -1)
[ -z "$MMC" ] && MMC=/tmp

LOG=$MMC/sensor-id.txt
SD=$(command -v sinfo || echo /usr/sbin/sinfo)
log() { echo "$*" >>"$LOG" 2>&1; }
: > "$LOG"
log "=== sensor identification $(date) ==="

# The sc2336p driver claims the sensor's I2C client; it must be unloaded
# (boot leaves it loaded only if probing got far enough).
if lsmod | grep -q 'sensor_sc2336p_t23'; then
	log "NOTE: sensor module loaded; removing it first"
	rmmod sensor_sc2336p_t23 2>/dev/null
	sleep 2
fi

log "--- dmesg probe history ---"
dmesg | grep -i 'sensor_detect\|sensor_sc2336\|is not an\|i2c.*0x30' >>"$LOG"

# sinfo handles the clock/reset sequence itself: enables MCLK output and
# toggles reset GPIO PA18 before each transaction. No power GPIO on this
# board, hence -p -1.
MCLK=27000000

log "--- sinfo probe: scan all addresses with MCLK on (PA18 reset dance) ---"
$SD -s t23 -b 0 -r 18 -p -1 -v probe >>"$LOG" 2>&1

log "--- SC-style ID window @0x30 @27MHz (SC2336P must answer 3107=0x9b 3108=0x3a) ---"
$SD -s t23 -b 0 -r 18 -p -1 -v dump 0x30 0x3107 0x3108 2 1 $MCLK >>"$LOG" 2>&1

log "--- retry @0x30 at 24MHz (rules out a 24MHz crystal variant) ---"
$SD -s t23 -b 0 -r 18 -p -1 -v dump 0x30 0x3107 0x3108 2 1 24000000 >>"$LOG" 2>&1

log "--- reproduce known responder @0x35, base window 0x3000-0x3011 ---"
$SD -s t23 -b 0 -r 18 -p -1 -v dump 0x35 0x3000 0x3011 2 1 $MCLK >>"$LOG" 2>&1

log "=== ID decode table (values straight from each driver's sensor_detect()) ==="
log "cv2003s0  addr 0x35: 0x3011 must be 0x20, 0x3138 must be 0x03 (cv2003s1 variant sits at 0x36)"
log "cv4002    addr 0x35: 0x3002 must be 0x02, 0x3003 must be 0x40"
log "cv3001/t31 addr 0x35: 0x3002 must be 0x01, 0x3003 must be 0x30"
log "cv4001/t31 addr 0x35: 0x3002 must be 0x01, 0x3003 must be 0x40"
log "cv2001/t31 addr 0x35: 0x3000/0x3001 = 0x20/0x03"
log "sc2336p   addr 0x30: 0x3107 must be 0x9b, 0x3108 must be 0x3a"
log "gc series: ID pair at 0x03f0 (high byte first), e.g. gc2083 = 0x20/0x83"

log "--- @0x35 explicit cv2003 pair (0x3011, then 0x3138) ---"
$SD -s t23 -b 0 -r 18 -p -1 -v dump 0x35 0x3011 0x3011 2 1 $MCLK >>"$LOG" 2>&1
$SD -s t23 -b 0 -r 18 -p -1 -v dump 0x35 0x3138 0x3138 2 1 $MCLK >>"$LOG" 2>&1

log "--- @0x35 explicit cv4002/t31-CV pair (0x3002, 0x3003) ---"
$SD -s t23 -b 0 -r 18 -p -1 -v dump 0x35 0x3002 0x3003 2 1 $MCLK >>"$LOG" 2>&1

log "--- @0x35 gc-style pair (0x03f0/0x03f1), just in case ---"
$SD -s t23 -b 0 -r 18 -p -1 -v dump 0x35 0x03f0 0x03f1 2 1 $MCLK >>"$LOG" 2>&1

# NOTE: the earlier manual i2cget values (3000=01 3002=05 3003=20 3008=02)
# were taken with MCLK off and no reset toggle, so they are not directly
# comparable to the dumps above - sinfo enables 27MHz MCLK and cycles PA18
# before each transaction. Expect values to change once the chip is clocked.

log "--- driver probe (captures its ID read only; module removed after) ---"
modprobe sensor_sc2336p_t23 >>"$LOG" 2>&1
sleep 4
dmesg | tail -15 >>"$LOG"
rmmod sensor_sc2336p_t23 2>/dev/null
$SD release >>"$LOG" 2>&1

log "=== done: pull sensor-id.txt off the card ==="
