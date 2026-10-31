# Benchmark against other Flutter video compression packages

Compresses the same videos with each package's 720p ("medium") preset, one
package after the other, on one phone. Every output is read back with the
same reader, and its picture is compared with the source on a computer.

## Results (2026-10-31)

Phone: Xiaomi 14T Pro (2407FPN8EG), MediaTek Dimensity 9300+, Android 16,
release build, Flutter 3.47.2. Two portrait camera videos from the same
phone, HEVC, 1080x1920 at 60 fps. Two runs each, the second in reverse order.

**Video A: 16.0 s, 41.5 MB**

| Package | Time, run 1 / run 2 | Size | Frame rate | SSIM | PSNR, dB |
|---|---|---|---|---|---|
| video_compress_next 0.1.0 | 4.2 s / 3.5 s | 7.60 MB | 30 | **0.9792** | **43.9** |
| media_compress_kit 0.1.0 | 5.7 s / failed | 7.98 MB | 60 | 0.9763 | 43.1 |
| video_compress 3.1.4 | 14.7 s / 14.1 s | 8.37 MB | 30 | 0.9789 | 43.5 |
| easy_video_editor 0.1.7 | 14.2 s / 14.9 s | 8.37 MB | 30 | 0.9789 | 43.5 |
| compress_video 1.0.0 | failed / failed | | | | |
| v_video_compressor 2.2.3 | failed / failed | | | | |

**Video B: 26.4 s, 68.0 MB**

| Package | Time, run 1 / run 2 | Size | Frame rate | SSIM | PSNR, dB |
|---|---|---|---|---|---|
| video_compress_next 0.1.0 | 5.3 s / 3.8 s | 12.36 MB | 30 | **0.9863** | **44.1** |
| media_compress_kit 0.1.0 | 7.7 s / 4.5 s | 12.80 MB | 58 | 0.9842 | 42.9 |
| video_compress 3.1.4 | 21.6 s / 9.7 s | 13.84 MB | 30 | 0.9853 | 41.8 |
| easy_video_editor 0.1.7 | 15.7 s / 10.2 s | 13.83 MB | 30 | 0.9853 | 41.8 |
| v_video_compressor 2.2.3 | failed / 5.0 s | 25.96 MB (HEVC) | 58 | not measured | |
| compress_video 1.0.0 | failed / failed | | | | |

Failures, from the packages' own errors:

- compress_video: `encoderUnavailable`, Media3 code 4003, no H.264 encoder
  for 1280x720 at 60 fps (it keeps the source frame rate) on every run.
- v_video_compressor: `Invalid Nal units` inside Media3 on three runs of four.
  Its "medium" keeps HEVC at about 7.9 Mbps, so the one success is twice the
  size of the others.
- media_compress_kit: `ERROR_CODE_FAILED_RUNTIME_CHECK` on one run of four.
- light_compressor 2.2.0 is not in the table: it does not build with
  Flutter 3.47 (no `namespace`, an engine on JitPack, Kotlin that no longer
  compiles).
- pro_video_editor is not in the table: it is an editor with layer rendering
  and has no single "compress to 720p" call to compare.

easy_video_editor compresses with the same transcoder as video_compress
(`com.otaliastudios:transcoder` 0.10.5), so its files are the same.

## Limits

One phone with one chip family, two videos of one kind (portrait, HEVC,
60 fps), two runs. Times vary between runs: the first read of a file comes
from flash, later ones from cache, and the phone warms up. compress_video
and v_video_compressor may work on other phones; they failed on this one.
Each package uses its own 720p preset, so bitrates differ; SSIM and PSNR
show what that buys.

## How quality is measured

`tool/ssim.py` turns both videos upright, scales them to 720 pixels on the
short side and compares every output frame with the source frame shown at
the same moment (ffmpeg `ssim` and `psnr` with `ts_sync_mode=nearest`).
Resampling both to 30 fps instead would compare frames 1/60 s apart for
packages that keep odd frames, and costs them about 0.03 SSIM.

## Running it

The app runs on start and logs one `BENCH {json}` line per run.

```bash
cd benchmark   # has .fvmrc: Flutter 3.47.2, which compress_video and v_video_compressor need
flutter build apk --release --target-platform android-arm64 \
  --dart-define=INPUTS=/storage/emulated/0/DCIM/Camera/a.mp4,/storage/emulated/0/DCIM/Camera/b.mp4
adb -s <serial> install -r build/app/outputs/flutter-apk/app-release.apk
adb -s <serial> shell pm grant io.github.zalexei.video_compress_next_example android.permission.READ_MEDIA_VIDEO
adb -s <serial> shell am start -n io.github.zalexei.video_compress_next_example/io.github.zalexei.vcn_benchmark.MainActivity
adb -s <serial> logcat -s flutter:I | grep BENCH
```

The outputs of the first run are kept in the app's
`files/bench` folder; build once more with `--dart-define=CHMOD_ONLY=true` and
start it to make them readable for `adb pull`, then
`python3 tool/ssim.py SOURCE.mp4 OUTPUT.mp4 ...`.

The app uses the example app's id on purpose: on Xiaomi phones an update
installs over USB without a confirmation on the phone, a new app does not.
