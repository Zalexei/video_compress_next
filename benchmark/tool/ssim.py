#!/usr/bin/env python3
"""SSIM and PSNR of compressed videos against their source, with ffmpeg.

    python3 tool/ssim.py SOURCE.mp4 OUTPUT.mp4 [OUTPUT.mp4 ...]

Both sides are turned upright (ffmpeg applies the rotation) and scaled to 720
pixels on the short side, so packages that pick different sizes are compared
on the same picture. Each output frame is compared with the source frame
shown at the same moment, so dropping 60 fps to 30 costs nothing by itself.
Prints one JSON line per output.
"""
import json
import re
import subprocess
import sys


def display_size(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height:stream_side_data=rotation", "-of", "json", path],
        capture_output=True, text=True, check=True).stdout
    stream = json.loads(out)["streams"][0]
    w, h = stream["width"], stream["height"]
    rotation = next((int(d["rotation"]) for d in stream.get("side_data_list", []) if "rotation" in d), 0)
    return (h, w) if rotation % 180 else (w, h)


def compare(source, output):
    w, h = display_size(source)
    short = min(w, h)
    cw, ch = (round(w * 720 / short / 2) * 2, round(h * 720 / short / 2) * 2)
    prep = f"scale={cw}:{ch}:flags=bicubic,setpts=PTS-STARTPTS"
    # The output is the main input: every output frame is paired with the
    # source frame nearest in time.
    sync = "shortest=1:ts_sync_mode=nearest"
    graph = (f"[0:v]{prep},split[a1][a2];[1:v]{prep},split[b1][b2];"
             f"[a1][b1]ssim={sync};[a2][b2]psnr={sync}")
    err = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", output, "-i", source,
         "-lavfi", graph, "-f", "null", "-"],
        capture_output=True, text=True).stderr
    ssim = re.search(r"SSIM .*All:([0-9.]+)", err)
    psnr = re.search(r"PSNR .*average:([0-9.inf]+)", err)
    return {"output": output.split("/")[-1],
            "ssim": float(ssim.group(1)) if ssim else None,
            "psnr": float(psnr.group(1)) if psnr else None}


if __name__ == "__main__":
    source, outputs = sys.argv[1], sys.argv[2:]
    for output in outputs:
        print(json.dumps(compare(source, output)), flush=True)
