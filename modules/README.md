# Experimental cv2005 sensor module (T23)

These two files came from the thingino build `jooan_c9ts_t23n_sc2336p_swt6621s`
(the WiFi variant used on the Jooan C92S-U) with the sensor driver swapped from
`sc2336p` to an experimental `cv2005` driver.

## What this is

Your I2C probe found the image sensor answering at address **0x35** with ID
registers `0x3002=0x05`, `0x3003=0x20` → chip ID **0x2005 (CV2005)**, a 5MP
MIPI sensor listed in Ingenic's Tx-SoC supported-sensor table (1920x1080,
2-lane, RGGB, RAW10). No driver for it existed in the pinned SDK tree, so this
driver was cloned from the same vendor family (cv4002/cv2003) and adjusted:

- **Permissive detect** — it logs every ID register it reads but never fails
  probe on a mismatch, so it binds even if the chip powers up in a different
  state. Watch `dmesg` for `cv2005` lines to see exactly what the chip said.
- Reset on **PA18**, powerdown pin disabled (matches your GPIO sweep: no
  separate sensor power rail found).
- IQ file `cv2005-t23.bin` — placeholder (sc2336p-tuned calibration). If the
  sensor streams, colors will be wrong until a real IQ file is made; that is
  expected and is a later step.

## Files

| File | sha256 |
|---|---|
| `sensor_cv2005_t23.ko` | `30981e1bfaaade2f654d6ab131186302b843fa494820b54f8c3ab9e96c3a373f` |
| `cv2005-t23.bin` | `cdc008699c55a68a2484d695a7325180450a53ff2bdf5f11c4b263ba176934db` |

`sensor_cv2005_t23.ko` vermagic: `3.10.14__isvp_pike_1.0__ preempt mod_unload
MIPS32_R1 32BIT` — matches the thingino T23 kernel.

## Install and test (no reflash needed)

On your PC, from the directory containing these two files:

```sh
scp sensor_cv2005_t23.ko cv2005-t23.bin root@<camera-ip>:/tmp/
ssh root@<camera-ip>
```

On the camera:

```sh
# unload whatever sensor driver is currently loaded, if any
grep cv2005 /proc/modules || true
rmmod sensor_sc2336p_t23 2>/dev/null; rmmod sensor_cv2005_t23 2>/dev/null

# install the module + IQ file (persistent across reboot, survives in flash? no - /usr is squashfs)
# so: load straight from /tmp first, keep it non-persistent
insmod /tmp/sensor_cv2005_t23.ko

# check what the driver saw
dmesg | grep -i -E 'cv2005|sensor' | tail -30

# if dmesg shows the sensor registered (no i2c errors from cv2005), start video
mkdir -p /usr/share/sensor
cp /tmp/cv2005-t23.bin /usr/share/sensor/   # read-only fs? if it fails, skip - raptor may find it via /tmp
raptor 2>&1 | tail -40                     # or: /etc/init.d/S31raptor restart
```

Note: `/usr` lives in a read-only squashfs, so the `cp` of the IQ file may fail.
That's fine for a first test — run `raptor` from the shell and read its output.

## What to send back

The `dmesg | grep cv2005` block and the `raptor` output. Either result is
useful:

- **Driver logs ID reads then registers cleanly** → sensor talks; any remaining
  problem is ISP/IQ tuning, which is solvable.
- **Driver logs but probe still times out** → the chip is held in reset or
  unpowered during module load; we then add power/reset sequencing to the
  driver and repeat.
- **Insmod itself fails (vermagic/Unknown symbol)** → paste the error; the
  module was built from the same tree as your running kernel so this should
  not happen.

## 18:36 build — register readback diagnostic

`sensor_cv2005_t23.ko` (sha256 `4261b257…`, 18.3 KiB) now verifies the init
table at stream-on: every register written by the driver is read back and
compared. This settles *why* there is no video:

- **`cv2005 DIAG[init]: MISMATCH reg 0x…` lines** → the chip ACKs every I2C
  byte but the write never lands (register file not clocked / core only
  partially powered) — confirms the partial-power-up theory.
- **`cv2005 DIAG[init]: N regs checked, 0 mismatched`** → all writes stick;
  the core is alive and suspicion moves to the MIPI PHY / lane side.
- **`read err` lines** → bus contention or the chip dropped off the bus.

Regs `0x3020`/`0x3021` are excluded from the check (the table writes the MIPI
clock port twice with different values — `0x60/0x09` early, `0x29/0x14` late;
the late pair wins). Send back the full `dmesg | grep cv2005` block after a
stream attempt and the verdict will be immediate.
