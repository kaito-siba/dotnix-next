"""チェキの下の縁に書く字 (LycoReco と日付) を、枠と同じだけ傾けた svg にする。

gpui では字も要素も回せないので、build の時に字の形を path にして回しておく。
日付は毎日変わるので、1.01 から 12.31 まで 366 日分を作る。

使い方: memo.py <太字の ttf> <中字の ttf> <傾き (度)> <出す folder>
folder (mod の folder) の memo/ に LycoReco.svg と date-<月>-<日>.svg を、folder に置き方を
書いた memo.js を出す。
"""

import json
import math
import sys
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

# 字の大きさ (px)。main.js の他の字と同じ単位
NAME_SIZE = 11
DATE_SIZE = 10.5


def outline(font, text, size, tilt, anchor):
    """text の形を、原点を baseline に置いて tilt 度回した path と、それを囲む箱にする。

    anchor が "start" なら原点は字の始まり、"end" なら終わり。箱は [左, 上, 幅, 高さ] で、
    原点からの px。
    """
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    names = [cmap[ord(ch)] for ch in text]
    width = sum(font["hmtx"][name][0] for name in names) * scale
    rad = math.radians(tilt)
    cos, sin = math.cos(rad), math.sin(rad)
    path = SVGPathPen(glyphs, ntos=lambda v: f"{v:.1f}")
    bounds = BoundsPen(glyphs)
    x = 0 if anchor == "start" else -width
    for name in names:
        # font の座標 (y は上向き) を px (y は下向き) にし、原点の周りに回す
        matrix = (scale * cos, scale * sin, scale * sin, -scale * cos, x * cos, x * sin)
        glyphs[name].draw(TransformPen(path, matrix))
        glyphs[name].draw(TransformPen(bounds, matrix))
        x += font["hmtx"][name][0] * scale
    left, top, right, bottom = bounds.bounds
    # 縁の滲みが切れないように、半 px ずつ広げる
    box = [round(left - 0.5, 2), round(top - 0.5, 2), round(right - left + 1, 2), round(bottom - top + 1, 2)]
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{box[2]}" height="{box[3]}" '
        f'viewBox="{box[0]} {box[1]} {box[2]} {box[3]}">'
        f'<path d="{path.getCommands()}" fill="currentColor"/></svg>\n'
    )
    return svg, box


def main():
    bold, medium, tilt, out = TTFont(sys.argv[1]), TTFont(sys.argv[2]), float(sys.argv[3]), Path(sys.argv[4])
    (out / "memo").mkdir(parents=True, exist_ok=True)
    boxes = {}
    svg, boxes["LycoReco"] = outline(bold, "LycoReco", NAME_SIZE, tilt, "start")
    (out / "memo" / "LycoReco.svg").write_text(svg)
    days = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    for month, count in enumerate(days, start=1):
        for day in range(1, count + 1):
            key = f"date-{month}-{day}"
            svg, boxes[key] = outline(medium, f"{month}.{day:02d}", DATE_SIZE, tilt, "end")
            (out / "memo" / f"{key}.svg").write_text(svg)
    (out / "memo.js").write_text(
        "// ./memo.py が build の時に書く。チェキの下の縁の字の svg を、原点 (baseline) からどこに置くか\n"
        f"export const TILT = {json.dumps(tilt)};\n"
        f"export const MEMO = {json.dumps(boxes)};\n"
    )


if __name__ == "__main__":
    main()
