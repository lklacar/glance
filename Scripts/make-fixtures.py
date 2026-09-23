"""Regenerate small, synthetic format fixtures. Requires Pillow with WebP and AVIF."""
from pathlib import Path
from PIL import Image, ImageDraw
import struct

out = Path(__file__).resolve().parent.parent / "Tests" / "Fixtures"
out.mkdir(parents=True, exist_ok=True)
a = Image.new("RGB", (80, 40), "#dd4422")
ImageDraw.Draw(a).rectangle((0, 0, 39, 19), fill="#2288cc")
b = Image.new("RGB", (80, 40), "#337755")
for ext in ["webp", "avif", "tga", "ppm", "jp2"]:
    a.save(out / f"still.{ext}")
for ext in ["gif", "webp", "png"]:
    a.save(out / f"animated.{ext}", save_all=True, append_images=[b], duration=[200, 300], loop=0)
a.save(out / "multipage.tiff", save_all=True, append_images=[b])
a.convert("CMYK").save(out / "cmyk.jpg")
Image.new("RGBA", (80, 40), (200, 100, 50, 128)).save(out / "transparent.png")
Image.new("I;16", (80, 40), 32000).save(out / "16bit.tiff")
# A minimal PSD with an uncompressed RGB composite and no layers or resources.
header = b"8BPS" + struct.pack(">H6sHIIHH", 1, bytes(6), 3, 40, 80, 8, 3)
planes = b"".join(channel.tobytes() for channel in a.split())
(out / "composite.psd").write_bytes(header + bytes(12) + bytes(2) + planes)
(out / "vector.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="80" height="40"><rect width="80" height="40" fill="#dd4422"/></svg>')
a.save(out / "document.pdf", resolution=72)
print(f"Wrote synthetic fixtures to {out}")
