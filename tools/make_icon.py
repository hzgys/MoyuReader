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

# ── 线条开卷图案 ──
cx = SIZE // 2
W = 34   # 主线条宽
w2 = 24  # 内页细节线宽

# 左半：顶边、外缘、底边（右半镜像）
top_l    = qbez((262, 344), (cx - 125, 360), (cx, 416))   # 外上 → 中缝顶（页面向中缝下斜）
side_l   = [(262, 344), (262, 648)]                        # 外缘竖边
bot_l    = qbez((262, 648), (cx - 125, 674), (cx, 706))   # 外下 → 中缝底

stroke(d, top_l, W)
stroke(d, side_l, W)
stroke(d, bot_l, W)
stroke(d, mirror_x(top_l), W)
stroke(d, mirror_x(side_l), W)
stroke(d, mirror_x(bot_l), W)

# 中缝
stroke(d, [(cx, 416), (cx, 706)], W)

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
