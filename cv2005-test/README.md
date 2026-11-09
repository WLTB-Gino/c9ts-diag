# CV2005 experimental sensor driver — Jooan C9TS / C92S-U (T23N, sensor @ 0x35)

Built 2026-11-09 from thingino-firmware `tf-swt6621s` tree
(`make CAMERA=jooan_c9ts_t23n_sc2336p_swt6621s br-ingenic-sdk-rebuild`).
Source of truth: `tf-swt6621s/overrides/ingenic-sdk/3.10.14/sensor-src/t23/cv2005.c`
(mirrored here as `cv2005.c`).

**One module, runtime-selectable configs.** No reflash between tests —
just `rmmod` / `insmod` with a different parameter.

## Files

| File | What it is | SHA-256 (first 16) |
|---|---|---|
| `sensor_cv2005_t23.ko` | Current build: REV-F variant param + settle adaptive (variant A baked in) | `7816c1c0b4074602` |
| `cv2005-t23.bin` | ISP IQ file (place as `cv2005.bin`) — placeholder IQ, colors will be off | `cdc008699c55a68a` |
| `cv2005.c` | Driver source mirror | — |
| `variants/cv2005-settle1-clk960.ko` | Older variant-A-only build (identical to current `.ko`; kept for checksum reference) | `7816c1c0b4074602` |
| `variants/sensor_cv2005_t23_revE-a-baseline.ko` | Older REV-E baseline (pre-0x3000 fix) | in `tf-swt6621s/revE-variants/` |

## What changed and why (history)

1. **Detect/port (Nov 8):** driver ported from cv2003s1, permissive detect for
   the 0x35 responder (chip_id reg reads 0x2003).
2. **Stream register fix (Nov 9, the big one):** the old cv2003s1-style stream
   control `0x0100` is **unmapped** on this chip (writes ACK, value never
   changes). All newer CV drivers (cv4002 t23, cv2001/3001/4001/5001 t41,
   cv8001 t40) stream via **`0x3000`: 0x00 = streaming, 0x01 = standby**.
   The port had been "streaming on" through a nonexistent register → sensor
   stayed in standby → silent MIPI, black stream. Fixed.
3. **REV-F bisection params:** `cv2005_variant=` insmod param
   - bit0 = cv4002 PLL (0x3024/25 = 70/03 instead of baseline 6C/02)
   - bit1 = cv4002 PHY block (0x3030, 0x3034–0x303F) + `0x3300 = 0x00`
4. **Variant A (settle adaptive):** `settle_time_apative_en` 0→1 baked in
   (attribute table, line ~380).

## Test procedure (over SSH)

```sh
scp sensor_cv2005_t23.ko root@<camera-ip>:/tmp/
ssh root@<camera-ip>

rmmod sensor_cv2005_t23 2>/dev/null
insmod /tmp/sensor_cv2005_t23.ko cv2005_variant=N      # N = 0,1,2,3
dmesg | tail -5        # expect: "cv2005 REV-F: variant=N (pll=... phy=... 3300=...)"
/etc/init.d/S31raptor restart    # trigger stream-on
dmesg | grep 'DIAG\[stream\]'
```

Expected healthy DIAG line: `0x3020=29 0x3021=14 ... 0x3000=0x00`, PLL bytes
matching the matrix column, `0x3300`/`0x3038` matching too. `0x0100` is the
negative control (unmapped, stays 0x00).

## Variant matrix

| variant | PLL 3024/25 | PHY 3038..3F block | 3300 | meaning |
|---|---|---|---|---|
| 0 | 6C/02 | baseline | 0x01 | REV-E baseline (control) |
| 1 | 70/03 | baseline | 0x01 | cv4002 PLL only |
| 2 | 6C/02 | cv4002 | 0x00 | cv4002 PHY+lane timing only |
| 3 | 70/03 | cv4002 | 0x00 | full cv4002-style |

**Test order (fastest bisection):** 3 → 2 → 1 → 0.
Variant 3 first (most likely if the chip is cv4002-class), 0 last as control.
Full runbook: `tf-swt6621s/revE-variants/TEST-MATRIX.md`.

## Success criteria

- DIAG shows `0x3000=0x00` + expected PLL/PHY values → writes landed
- Stream shows **non-black frames** → that's our working config; stop and report
- If DIAG values come back 0xff/0x00 where data is expected → NACK/RAZ, note it

## Ground-truth rules learned on this hardware

- I2C ACK ≠ verified: RAZ registers ACK. Only MIPI CSI output is truth.
- The chip is only responsive while the `.ko` is loaded (rmmod → i2ctransfer
  dies with I2C_RDWR I/O error): it needs SoC-driven MCLK, no independent rail.
- Always `rmmod` before loading any other build.
