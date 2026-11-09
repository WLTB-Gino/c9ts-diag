#!/bin/sh
# parse-stock-ko.sh — ground-truth extraction from a stock sensor_cv2005.ko
# Usage: ./parse-stock-ko.sh <path-to-ko> [output-dir]
# Expect sha256 e5080976a0f9d45e6621746a325fa26e13783ecb558d10d160c7848157f310ca
# (W3-U build; a C92S-U build may differ — print it, don't gate on it).
set -eu
KO="${1:?usage: parse-stock-ko.sh <ko-file> [outdir]}"
OUT="${2:-stock-ko-analysis}"
mkdir -p "$OUT"

echo "=== IDENTITY ==="
sha256sum "$KO"
ls -l "$KO"
file "$KO" 2>/dev/null || true

echo; echo "=== STRINGS (sensor/isp/version) ==="
strings -n 6 "$KO" | grep -iE 'cv2005|sensor|isp|3\.10|isvp|mipi|1080|1920|2304|2592|license|GPL' | sort -u | tee "$OUT/strings-sensor.txt" | head -60

echo; echo "=== INIT TABLE SCAN ==="
# Stock Ingenic sensor modules store init lists as {u16 BE addr, u8 val} = 3 bytes/entry.
# Key registers: stream-on 0100, standby 3000, MIPI/VTS 3020 3021, PLL 3024 3025 3038,
# MIPI ctrl 3300. Find each as byte triplet, dump context.
python3 - "$KO" "$OUT" <<'EOF'
import sys
data = open(sys.argv[1], 'rb').read()
regs = [0x0100, 0x3000, 0x3020, 0x3021, 0x3024, 0x3025, 0x3038, 0x3300]
for r in regs:
    pat = bytes([r >> 8, r & 0xff])
    n, start = 0, 0
    while True:
        i = data.find(pat, start)
        if i < 0: break
        n += 1; start = i + 1
    print("REG 0x%04x: %d triplet-hits" % (r, n))
EOF

echo; echo "=== CONTEXT DUMPS (64 bytes around first hits) ==="
python3 - "$KO" "$OUT" <<'EOF' || true
import sys, re
data = open(sys.argv[1], 'rb').read()
outdir = sys.argv[2]
regs = [0x0100, 0x3000, 0x3020, 0x3021, 0x3024, 0x3025, 0x3038, 0x3300]
lines = []
for r in regs:
    pat = bytes([r >> 8, r & 0xff])
    idxs, start = [], 0
    while True:
        i = data.find(pat, start)
        if i < 0 or len(idxs) >= 8: break
        idxs.append(i); start = i + 1
    lines.append(f"REG 0x{r:04x}: {len(idxs)} hit(s) at {idxs}")
    for i in idxs[:4]:
        ctx = data[max(0,i-32):i+64]
        lines.append("  ctx@%d: %s" % (i, ctx.hex()))
open(f"{outdir}/table-context.txt", "w").write("\n".join(lines) + "\n")
print("\n".join(lines[:20]))
EOF

echo; echo "=== 3-BYTE CHAIN SCAN ({u16 addr, u8 val} runs >= 12 entries) ==="
python3 - "$KO" "$OUT" <<'EOF' || true
import sys
data = open(sys.argv[1], 'rb').read()
best = []
i = 0
n = len(data)
while i < n - 3:
    run = 0
    j = i
    while j + 2 < n and 0x3000 <= (data[j] << 8 | data[j+1]) <= 0x3fff:
        run += 1; j += 3
    if run >= 12:
        best.append((i, run))
        i = j
    else:
        i += 1
out = []
for off, run in best[:20]:
    seq = data[off:off + run*3]
    out.append(f"chain@0x{off:x} ({run} entries):")
    for k in range(0, len(seq), 3):
        a = seq[k] << 8 | seq[k+1]; v = seq[k+2]
        out.append(f"  0x{a:04x}=0x{v:02x}")
open(f"{outdir}/init-chains.txt", "w").write("\n".join(out) + "\n")
print(f"{len(best)} chain(s) found; first at 0x{best[0][0]:x} len {best[0][1]}" if best else "no long register chains found — table may use u16 LE or struct layout")
EOF

echo; echo "Done. Artifacts in $OUT/: strings-sensor.txt ko.hex table-context.txt init-chains.txt"
echo "Next: diff init-chains.txt vs REV-F table in cv2005-test/cv2005.c (0x3020=0x60 0x3021=0x09 @425; 0x3020=0x29 0x3021=0x14 @466)"
