#!/usr/bin/env python3
"""生成 MoyuReader App 图标：白色圆角方块 + 深色线条开卷图案 → assets/AppIcon.icns"""
import math, os, subprocess, sys
from PIL import Image, ImageDraw

SIZE = 1024
INK = (43, 47, 52, 255)        # 深炭色线条
BG = (252, 252, 254, 255)      # 近白背景
BORDER = (222, 225, 230, 255)  # 浅灰描边
STROKE = 42

def qbez(p0, p1, p2, n=48):
    """二次贝塞尔曲线采样点"""
    return [((1-t)**2*p0[0] + 2*(1-t)*t*p1[0] + t**2*p2[0],
             (1-t)**2*p0[1] + 2*(1-t)*t*p1[1] + t**2*p2[1])
            for t in (i/n for i in range(n+1))]

def stroke(draw, pts, w=STROKE):
    """圆头粗线条：line + 两端圆帽"""
    draw.line(pts, fill=INK, width=w, joint="curve")
    r = w / 2
    for x, y in (pts[0], pts[-1]):
        draw.ellipse((x-r, y-r, x+r, y+r), fill=INK)

def mirror_x(pts):
    return [(SIZE - x, y) for x, y in pts]

img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# ── 背景：Apple 风格 squircle（1024 画布，图标体 824，圆角率 22.37%）──
d.rounded_rectangle((100, 100, 924, 924), radius=184, fill=BG, outline=BORDER, width=6)

# ── 开卷图案 ──
cx = SIZE // 2
# 左页四个锚点：内上 / 外上 / 外下 / 内下
s_t = (cx, 400)
o_t = (268, 348)
o_b = (268, 646)
s_b = (cx, 694)

# 顶边（微弧，像摊开的页面）
top_l = qbez(s_t, (cx - 130, 372), o_t)
# 外侧竖边
side_l = [o_t, o_b]
# 底边（微弧）
bot_l = qbez(o_b, (cx - 130, 668), s_b)

left_outline = top_l + side_l[1:] + bot_l
stroke(d, left_outline)
stroke(d, mirror_x(left_outline))

# 中缝
stroke(d, [s_t, s_b])

# 页面层次线：每页内侧一条平行于底边的弧
page_l = qbez((cx - 60, 660), (cx - 160, 640), (312, 618))
stroke(d, page_l, w=30)
stroke(d, mirror_x(page_l), w=30)

out_dir = os.path.join(os.path.dirname(__file__), "..", "assets")
os.makedirs(out_dir, exist_ok=True)
png = os.path.join(out_dir, "icon_1024.png")
img.save(png)

# ── iconset → icns ──
iconset = os.path.join(out_dir, "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)
for s in (16, 32, 64, 128, 256, 512, 1024):
    im = img.resize((s, s), Image.LANCZOS)
    name = f"icon_{s}x{s}.png" if s <= 512 else "icon_512x512@2x.png"
    im.save(os.path.join(iconset, name))
    if s in (16, 32, 128, 256, 512):
        half = s // 2
        img.resize((half, half), Image.LANCZOS).save(
            os.path.join(iconset, f"icon_{half}x{half}@2x.png"))

icns = os.path.join(out_dir, "AppIcon.icns")
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)
print("OK:", os.path.abspath(icns))
