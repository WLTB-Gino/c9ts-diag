# CV2005 experimental sensor test — Jooan C92S-U (T23)

Built 2026-11-08 03:27 from thingino-firmware `tf-swt6621s` tree.

| File | What it is | SHA-256 |
|---|---|---|
| `sensor_cv2005_t23.ko` | Sensor driver module (17.7 KiB, MIPS32, vermagic `3.10.14__isvp_pike_1.0__`, depends `tx-isp-t23`) | `3a28c724ea270353e1834333baf157ae4fcd7ef09d60cfce2485237d27e05201` |
| `cv2005-t23.bin` | ISP IQ file (place as `cv2005.bin`) | `cdc008699c55a68a2484d695a7325180450a53ff2bdf5f11c4b263ba176934db` |
| `cv2005.c` | Driver source (ported from cv4002, permissive detect) | — |

This works on the image **already flashed** on the camera (kernel is
`3.10.14__isvp_pike_1.0__`, no MODVERSIONS → symbol names only, vermagic matches).
**No reflash needed.**

## Test procedure (over SSH)

```sh
# from your PC:
scp sensor_cv2005_t23.ko cv2005-t23.bin root@192.168.20.113:/tmp/
ssh root@192.168.20.113
```

On the camera:

```sh
# 1. unload the old (dead) sensor driver if it's loaded
rmmod sensor_sc2336p_t23 2>/dev/null

# 2. load the cv2005 driver
insmod /tmp/sensor_cv2005_t23.ko

# 3. check what the chip said
dmesg | grep -i cv2005 | tail -20

# 4. try to get a stream
/etc/init.d/S31raptor restart
```

## Reading the result

- **`probe ok ------->cv2005`** in dmesg → driver bound the chip. Check the web
  UI / RTSP stream next. Colors WILL be wrong (IQ file is a placeholder) —
  that's fine, it proves the pipeline.
- **`cv2005 detect: ... ret = -5`** on all four ID reads → the chip is not
  responding at runtime (power sequencing issue). Copy the dmesg output back to us.
- **insmod fails with "unknown symbol" or "invalid module format"** → kernel
  mismatch; the full integrated image would be needed instead.

## What this driver does differently

Permissive detect: it logs all four ID register reads
(`0x3011`, `0x3138` cv2003-style and `0x3002`, `0x3003` cv2005-style) and binds
regardless of the value, so we always get an attach + full register log instead
of a silent `-ENODEV`.

## Making it permanent

The full image (`autoupdate-full.bin`, built 2026-11-08 03:46) now ships this
driver with its autoload entry (`/etc/modules.d/30-sensor`) and the IQ file
(`/usr/share/sensor/cv2005-t23.bin`). Once the `/tmp` test above shows
`probe ok`, flashing that image makes everything permanent — no manual insmod
after that. Until then, every reboot returns to the old sc2336p attempt
(harmless; it fails silently to `/tmp` and the old BUG spam continues).
