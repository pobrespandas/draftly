import importlib.util
from pathlib import Path
import tempfile
import unittest
from PIL import Image, ImageDraw

spec = importlib.util.spec_from_file_location("capture", Path(__file__).with_name("check-visual-capture.py"))
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


class CaptureTests(unittest.TestCase):
    def inspect(self, image, points):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "capture.png"
            image.save(path)
            return capture.inspect_capture(path, points)

    def test_rejects_one_x_content_in_two_x_canvas(self):
        image = Image.new("RGB", (200, 160), "white")
        ImageDraw.Draw(image).rectangle((0, 0, 99, 79), fill="#eeeeee")
        result = self.inspect(image, (100, 80))
        self.assertTrue(result["whitePaddingDetected"])
        self.assertFalse(result["usableForFullWindowMeasurement"])

    def test_accepts_full_sidebar_at_one_or_two_x(self):
        for scale in (1, 2):
            image = Image.new("RGB", (100 * scale, 80 * scale), "white")
            ImageDraw.Draw(image).rectangle((0, 0, 20 * scale, 80 * scale), fill="#eeeeee")
            self.assertTrue(self.inspect(image, (100, 80))["usableForFullWindowMeasurement"])

    def test_rejects_wrong_window_size(self):
        image = Image.new("RGB", (200, 160), "gray")
        self.assertFalse(self.inspect(image, (103, 80))["usableForFullWindowMeasurement"])

    def test_rejects_blank_capture(self):
        self.assertFalse(self.inspect(Image.new("RGB", (200, 160), "white"), (100, 80))["usableForFullWindowMeasurement"])
