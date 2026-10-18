"""Generate a small but real sample textbook PDF for demos/tests."""
from pathlib import Path


def make_sample_textbook(out: Path) -> Path:
    import pymupdf
    from PIL import Image, ImageDraw

    # a simple programmatic diagram image (shapes/text only — no AI image generation)
    img = Image.new("RGB", (640, 400), (240, 248, 240))
    d = ImageDraw.Draw(img)
    d.ellipse([260, 30, 380, 150], fill=(250, 204, 21), outline=(0, 0, 0), width=3)
    d.text((285, 165), "SUNLIGHT", fill=(0, 0, 0))
    d.rounded_rectangle([220, 230, 420, 330], 18, fill=(34, 197, 94), outline=(0, 0, 0), width=3)
    d.text((255, 275), "LEAF (chlorophyll)", fill=(255, 255, 255))
    d.line([320, 150, 320, 230], fill=(0, 0, 0), width=4)
    d.polygon([(320, 230), (310, 212), (330, 212)], fill=(0, 0, 0))
    d.text((30, 350), "Water + Carbon dioxide  ->  Glucose + Oxygen", fill=(0, 0, 0))
    png = out.parent / "_diagram.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(png)

    doc = pymupdf.open()
    pages = [
        ("Chapter 6: Life Processes — Photosynthesis",
         "Photosynthesis is the process by which green plants make their own food. "
         "Plants use sunlight, water and carbon dioxide to produce glucose and oxygen. "
         "This process takes place in chloroplasts, which contain the green pigment chlorophyll. "
         "Photosynthesis is essential for life on Earth because it produces the oxygen we breathe and forms the base of most food chains."),
        ("How Photosynthesis Works",
         "The process of photosynthesis can be divided into two stages. In the light-dependent stage, sunlight is captured by chlorophyll and water molecules are split, releasing oxygen. "
         "In the second stage, carbon dioxide is converted into glucose using the energy captured earlier. "
         "The equation for photosynthesis is: 6CO2 + 6H2O + sunlight -> C6H12O6 + 6O2. "
         "Figure 6.1 shows sunlight falling on a leaf. Stomata on the leaf surface allow carbon dioxide to enter."),
        ("Factors Affecting Photosynthesis",
         "The rate of photosynthesis depends on light intensity, carbon dioxide concentration, temperature and water availability. "
         "Farmers use this knowledge in greenhouses to grow crops faster. "
         "A common mistake is to think plants perform photosynthesis only during the day and respiration only at night; in reality respiration happens all the time. "
         "Desert plants open their stomata at night to reduce water loss."),
        ("Summary and Questions",
         "Photosynthesis converts light energy into chemical energy stored in glucose. "
         "It needs sunlight, chlorophyll, carbon dioxide and water, and it releases oxygen. "
         "Questions: 1) What is photosynthesis? 2) Write the equation for photosynthesis. 3) Why is photosynthesis important for animals?"),
    ]
    for title, body in pages:
        page = doc.new_page(width=595, height=842)
        page.insert_textbox(pymupdf.Rect(50, 50, 545, 110), title, fontsize=17)
        page.insert_textbox(pymupdf.Rect(50, 120, 545, 500), body, fontsize=11.5)
    # embed the diagram on page 2 (index 1)
    doc[1].insert_image(pymupdf.Rect(120, 480, 475, 700), filename=str(png))
    doc.set_metadata({"title": "Class 10 Science — Life Processes (Sample Textbook)"})
    doc.save(out)
    png.unlink(missing_ok=True)
    return out
