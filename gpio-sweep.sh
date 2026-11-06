#!/bin/sh
# ---------------------------------------------------------------
# C92S-U (JA-6621-SL V1.0) sensor POWER-GPIO sweep (gpio-sweep.sh)
# Hypothesis: sensor VDD_IO/DVDD/AVDD LDO enable is held LOW by an
# unconfigured GPIO -> die silent on every I2C address.
# Method: drive each candidate GPIO high then low; after each state
# run sinfo probe (MCLK + PA18 reset handled by sinfo) and a raw
# i2cdetect; a NEW responder vs baseline = candidate found.
# Read-only wrt config. No insmod, no stream-on, no writes to /etc.
# Camera may reboot if a candidate GPIO is load-bearing: the log is
# synced line-by-line, so re-run resumes visibility of what killed it.
# Output: gpio-sweep.log next to this script on the SD card.
# ---------------------------------------------------------------
SD=$(cd "$(dirname "$0")" && pwd)
L="$SD/gpio-sweep.log"
BUS=0
RESET=18

# Ordered by Jooan-family likelihood. Excluded: 0-5 (SPI NOR flash!),
# 6 (wlan), 17 (motor switch), 18 (sensor reset, sinfo uses it),
# 49/50 (ircut), 51-54 (motors), 59-63 (ir850/white/mmc_cd/btn/spk).
CAND="16 7 19 20 21 22 23 8 9 10 11 12 13 14 15 \
39 40 41 42 43 44 45 46 47 48 \
64 65 66 67 68 69 70 71 \
24 25 26 27"

exportg() {
    echo "$1" > /sys/class/gpio/export 2>/dev/null
    echo out > /sys/class/gpio/gpio"$1"/direction 2>/dev/null
}
setg() { echo "$2" > /sys/class/gpio/gpio"$1"/value 2>/dev/null; }
relg() {
    echo in > /sys/class/gpio/gpio"$1"/direction 2>/dev/null
    echo "$1" > /sys/class/gpio/unexport 2>/dev/null
}
snap() { i2cdetect -y "$BUS" 2>/dev/null; }

{
echo "===== C92S-U sensor power-GPIO sweep $(date) ====="
echo "board: JA-6621-SL V1.0 / sensor bd JD25S / SoC T23N"

echo "--- unload possibly-probing sensor driver ---"
rmmod sensor_sc2336p_t23 2>/dev/null && echo "sc2336p unloaded" || echo "no driver loaded"
sleep 1

echo
echo "--- baseline: all candidates Hi-Z, sensor presumed unpowered ---"
snap
echo "$CAND" | tr ' ' '\n' | while read g; do [ -n "$g" ] && relg "$g"; done
sleep 1
BASE=$(snap)
echo "$BASE"
echo "(0x35 expected: the 642A/543TC peripheral chip, NOT the sensor)"
sync

FOUND=""
for g in $CAND; do
    echo
    echo "--- candidate GPIO $g ---"
    exportg "$g"
    for v in 1 0; do
        setg "$g" "$v"
        sleep 0.2
        echo "state: GPIO $g = $v"
        sinfo -s t23 -b "$BUS" -r "$RESET" -v probe 2>&1 | grep -v '^$'
        NOW=$(snap)
        if [ "$BASE" != "$NOW" ]; then
            echo ">>> NEW BUS STATE with GPIO $g=$v:"
            echo "$NOW"
            # SC-style ID pair attempt on any fresh low-bus responder
            for a in 30 32 33 34 36; do
                R7=$(i2ctransfer -y "$BUS" w@0x$a 0x31 0x07 r@0x$a 1 2>/dev/null)
                R8=$(i2ctransfer -y "$BUS" w@0x$a 0x31 0x08 r@0x$a 1 2>/dev/null)
                [ -n "$R7" ] && echo "addr 0x$a: 0x3107=0x$R7 0x3108=0x$R8"
            done
            FOUND="$FOUND $g=$v"
        fi
        sync
    done
    relg "$g"
    sleep 0.1
done

echo
echo "===== SWEEP RESULT ====="
if [ -n "$FOUND" ]; then
    echo "RESPONDER APPEARED WITH:$FOUND"
    echo "next: isolate which state is POWER (vs stray pull-up), then read IDs"
else
    echo "no candidate produced a new I2C responder."
    echo "=> sensor power is likely NOT a plain GPIO toggle (hard-wired rail)"
    echo "   or it is on a pin outside this candidate set."
fi
echo
echo "--- final dmesg tail ---"
dmesg | tail -20
echo "===== sweep complete $(date) ====="
} >> "$L" 2>&1

exit 0
