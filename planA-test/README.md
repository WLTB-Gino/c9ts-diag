# Plan-A test — stock Jooan cv2005 driver + IQ on the C9TS

**Payload:** the byte-verified STOCK `sensor_cv2005.ko` recovered from the
W8-U donor flash, plus the stock IQ file. This is the ground-truth test:
if the stock driver produces a picture on our camera, our port gets fixed
from its tables; if the stock driver is also black, the fault is at the
hardware/ISP level, not in driver code.

| File | SHA-256 |
|---|---|
| `sensor_cv2005.ko` | `e5080976a0f9d45e6621746a325fa26e13783ecb558d10d160c7848157f310ca` |
| `cv2005-t23.bin` (staged as `/etc/sensor/cv2005.bin`) | `1081b40d0179695f8ee597213333eb99aab4f895b529c7d3f1aa1d1acf7ad4f4` |

## Card layout

```
SD root/
├── runonce.sh          ← copy of planA-test/runonce.sh
├── planA-test/
│   ├── sensor_cv2005.ko
│   └── cv2005-t23.bin
└── (runonce.done DELETED if present)
```

## Procedure

1. Copy `planA-test/` to the SD card root.
2. Copy `planA-test/runonce.sh` to the card root (this is the file that
   auto-runs at boot).
3. Delete `runonce.done` from the card root if it's there.
4. Card in, power up, wait ~2 minutes.
5. Pull `planA-test.log` off the card AND open the camera web UI live view.

## Outcomes

- **Web UI shows a real picture** → stock driver works. We diff its init
  tables against our port and fix our build. Send the log anyway.
- **Still black** → stock is black too. That's hardware/ISP territory
  (REV-G diag and MCLK/power hypotheses come back into play). The log's
  dmesg tail will show whether the stock module even probed.

## Undo

- Module: power-cycle (boot always loads the profile's sc2336p module).
- IQ: `rm /etc/sensor/cv2005.bin` — unless `.planA-backup` exists, then
  `mv /etc/sensor/cv2005.bin.planA-backup /etc/sensor/cv2005.bin`.

## Notes

- The script hashes both files on-card and logs them; compare against the
  table above (first 16 hex chars are enough) before trusting results.
- IQ is staged BEFORE `insmod` — the ISP reads it when the sensor module
  registers, so order matters.
- Safe: read-only w.r.t. stored config; module state self-restores on
  reboot; no flash writes anywhere in this test.
