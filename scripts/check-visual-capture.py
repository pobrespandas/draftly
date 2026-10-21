#!/usr/bin/env python3
"""Check capture size and reject the observed white-padding defect. Requires Pillow."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops


def inspect_capture(path, points):
    with Image.open(path) as source:
        image = source.convert("RGB")
    width, height = image.size
    scale_x, scale_y = width / points[0], height / points[1]
    half_x, half_y = width // 2, height // 2
    def white(rect):
        region = image.crop(rect)
        red, green, blue = region.split()
        minimum = ImageChops.darker(ImageChops.darker(red, green), blue)
        dark_pixels = sum(minimum.histogram()[:248])
        # Ignore isolated compression pixels in an otherwise empty half.
        return dark_pixels <= max(4, region.width * region.height // 100000)
    padded = white((half_x, 0, width, height)) and white((0, half_y, width, height))
    reasons = []
    if abs(scale_x - scale_y) > 0.002 or not any(abs(scale_x - value) < 0.002 for value in (1, 2)):
        reasons.append("Pixel dimensions do not match the stated point dimensions at 1x or 2x.")
    if padded:
        reasons.append("The right and bottom halves are white. Reject this capture for full-window measurements.")
    return {"file": str(path), "pixels": [width, height], "windowPoints": list(points),
            "canvasScale": [scale_x, scale_y], "whitePaddingDetected": padded,
            "usableForFullWindowMeasurement": not reasons, "reasons": reasons}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--points", nargs=2, type=int, required=True, metavar=("WIDTH", "HEIGHT"))
    args = parser.parse_args()
    if min(args.points) <= 0:
        parser.error("Point dimensions must be positive.")
    result = inspect_capture(args.image, args.points)
    print(json.dumps(result, indent=2))
    return 0 if result["usableForFullWindowMeasurement"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
