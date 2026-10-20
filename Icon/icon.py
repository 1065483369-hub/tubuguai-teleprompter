# -*- coding: utf-8 -*-
"""
「兔不乖的提词器」App 图标。
基准 1024×1024，纯矢量，任何尺寸都锐利。

设计取向 —— 为什么长这样：
  · 主体是一只兔子的头，占画面上 2/3。耳朵是兔子识别度最高的部件，
    所以给足长度和倾斜；一只立、一只歪，"不乖"藏在这个细节里。
  · 下方 1/3 是提词板，板上是真实的汉字「你好」+「今天」，
    前者绿（已读）、后者白带绿底（光标）。图标直接把
    「读到哪亮到哪」这个核心机制画出来，扫一眼就知道是提词器。
  · 用描边 + 内阴影做出体积，不是几个色块拼贴。
    暖白毛色配深蓝底，在 App 库的深色背景里也不糊。
"""

FUR_LIT   = '#FFFBF5'   # 毛色高光面
FUR       = '#F4EDE3'   # 毛色主面
FUR_SHADE = '#DFD4C6'   # 毛色暗面
OUTLINE   = '#2B2622'   # 轮廓线
INNER_EAR = '#F0A8BC'   # 耳内粉
BLUSH     = '#F5B9C8'
READ      = '#4ADE80'   # 已读绿
NOW       = '#FFFFFF'   # 光标白
BOARD_TOP = '#1B2330'
BOARD_BOT = '#0C1118'
BOARD_EDGE = '#38445A'


def build(size: int = 1024) -> str:
    u = size / 1024.0

    def p(v: float) -> float:
        return round(v * u, 2)

    o = [
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'width="{s}" height="{s}" viewBox="0 0 {s} {s}">'.format(s=size)
    ]

    # ── 渐变与滤镜。有光影才有体积，纯色块看着就是贴纸 ──
    o.append(
        '<defs>'
        # 背景：深蓝到近黑，让暖白的兔子跳出来
        '<radialGradient id="bg" cx="50%" cy="34%" r="78%">'
        '<stop offset="0" stop-color="#2A3A52"/>'
        '<stop offset="0.55" stop-color="#16202E"/>'
        '<stop offset="1" stop-color="#0A0E14"/>'
        '</radialGradient>'
        # 毛色：左上受光、右下入暗
        '<linearGradient id="fur" x1="18%" y1="8%" x2="82%" y2="96%">'
        '<stop offset="0" stop-color="{lit}"/>'
        '<stop offset="0.52" stop-color="{mid}"/>'
        '<stop offset="1" stop-color="{sh}"/>'
        '</linearGradient>'
        '<linearGradient id="ear" x1="30%" y1="0%" x2="70%" y2="100%">'
        '<stop offset="0" stop-color="#F7BDCD"/>'
        '<stop offset="1" stop-color="#E48EA6"/>'
        '</linearGradient>'
        # 提词板：上亮下暗，像一块真的屏
        '<linearGradient id="board" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="{bt}"/>'
        '<stop offset="1" stop-color="{bb}"/>'
        '</linearGradient>'
        # 屏幕顶部的一道反光
        '<linearGradient id="glare" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.14"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>'
        '</linearGradient>'
        # 兔子落在板上的投影
        '<filter id="drop" x="-30%" y="-30%" width="160%" height="160%">'
        '<feDropShadow dx="0" dy="{dy}" stdDeviation="{sd}" '
        'flood-color="#000" flood-opacity="0.34"/>'
        '</filter>'
        '<filter id="soft" x="-30%" y="-30%" width="160%" height="160%">'
        '<feDropShadow dx="0" dy="{dy2}" stdDeviation="{sd2}" '
        'flood-color="#000" flood-opacity="0.22"/>'
        '</filter>'
        '</defs>'.format(lit=FUR_LIT, mid=FUR, sh=FUR_SHADE,
                         bt=BOARD_TOP, bb=BOARD_BOT,
                         dy=p(14), sd=p(18), dy2=p(8), sd2=p(10))
    )
    o.append('<rect width="{s}" height="{s}" fill="url(#bg)"/>'.format(s=size))

    stroke = p(13)          # 轮廓线宽，统一

    # ── 耳朵。先画后面那只，形成前后层次 ──
    def ear(cx, cy, rx, ry, tilt):
        return (
            '<g transform="rotate({t} {cx} {cy})">'
            '<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" '
            'fill="url(#fur)" stroke="{ol}" stroke-width="{sw}"/>'
            '<ellipse cx="{cx}" cy="{icy}" rx="{irx}" ry="{iry}" '
            'fill="url(#ear)"/>'
            '</g>'.format(t=tilt, cx=p(cx), cy=p(cy), rx=p(rx), ry=p(ry),
                          icy=p(cy + ry * 0.10), irx=p(rx * 0.44),
                          iry=p(ry * 0.66), ol=OUTLINE, sw=stroke)
        )

    o.append('<g filter="url(#soft)">')
    o.append(ear(618, 240, 66, 176, 24))     # 歪的那只，在后
    o.append(ear(354, 232, 66, 176, -14))    # 立着的，在前
    o.append('</g>')

    # ── 头。略扁的椭圆比正圆更像兔子 ──
    o.append(
        '<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" '
        'fill="url(#fur)" stroke="{ol}" stroke-width="{sw}" '
        'filter="url(#drop)"/>'.format(
            cx=p(486), cy=p(452), rx=p(246), ry=p(212),
            ol=OUTLINE, sw=stroke)
    )
    # 额头高光，撑出球面感
    o.append(
        '<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" '
        'fill="#FFFFFF" opacity="0.30"/>'.format(
            cx=p(418), cy=p(374), rx=p(92), ry=p(58))
    )

    # ── 眼睛。一睁一眨，配合"不乖" ──
    # 睁眼：瞳孔 + 两处反光，才有神
    o.append('<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{ol}"/>'
             .format(cx=p(398), cy=p(446), rx=p(32), ry=p(41), ol=OUTLINE))
    o.append('<circle cx="{cx}" cy="{cy}" r="{r}" fill="#FFF" opacity="0.95"/>'
             .format(cx=p(410), cy=p(430), r=p(12)))
    o.append('<circle cx="{cx}" cy="{cy}" r="{r}" fill="#FFF" opacity="0.55"/>'
             .format(cx=p(388), cy=p(462), r=p(6)))
    # 眨眼：一道弧线 + 睫毛感的收尾
    o.append(
        '<path d="M{x1} {y1} Q{cx} {cy} {x2} {y2}" stroke="{ol}" '
        'stroke-width="{sw}" fill="none" stroke-linecap="round"/>'.format(
            x1=p(538), y1=p(452), cx=p(580), cy=p(418),
            x2=p(620), y2=p(450), ol=OUTLINE, sw=p(17))
    )

    # ── 鼻子：Y 字形，兔子的标志 ──
    o.append(
        '<path d="M{nx} {ny} l{dx} {dy} l{dx2} 0 z" fill="{pk}" '
        'stroke="{ol}" stroke-width="{sw}" stroke-linejoin="round"/>'.format(
            nx=p(486), ny=p(520), dx=p(-26), dy=p(-24), dx2=p(52),
            pk=INNER_EAR, ol=OUTLINE, sw=p(9))
    )
    # 嘴：人字形
    o.append(
        '<path d="M{x} {y} V{y2} M{x} {y2} Q{qx1} {qy} {ex1} {ey} '
        'M{x} {y2} Q{qx2} {qy} {ex2} {ey}" stroke="{ol}" '
        'stroke-width="{sw}" fill="none" stroke-linecap="round"/>'.format(
            x=p(486), y=p(520), y2=p(558),
            qx1=p(452), qx2=p(520), qy=p(580),
            ex1=p(426), ex2=p(546), ey=p(568),
            ol=OUTLINE, sw=p(12))
    )

    # ── 腮红 ──
    for cx in (318, 654):
        o.append('<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" '
                 'fill="{b}" opacity="0.5"/>'.format(
                     cx=p(cx), cy=p(512), rx=p(40), ry=p(25), b=BLUSH))

    # ── 胡须。三根一侧，细线，别抢主体 ──
    for side, base in ((-1, 264), (1, 708)):
        for i, (dy, dl) in enumerate(((-16, 62), (4, 70), (24, 60))):
            o.append(
                '<path d="M{x} {y} l{dx} {dy2}" stroke="{ol}" '
                'stroke-width="{sw}" stroke-linecap="round" opacity="0.42"/>'
                .format(x=p(base), y=p(512 + dy), dx=p(side * dl),
                        dy2=p(dy * 0.35), ol=OUTLINE, sw=p(7))
            )

    # ── 提词板。真实文字比色条更能说明"这是提词器" ──
    bx, by, bw, bh = 372, 706, 452, 186
    o.append(
        '<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" '
        'fill="url(#board)" stroke="{ol}" stroke-width="{sw}" '
        'filter="url(#drop)"/>'.format(
            x=p(bx), y=p(by), w=p(bw), h=p(bh), r=p(30),
            ol=OUTLINE, sw=stroke)
    )
    # 屏幕内边界，做出"屏"的厚度
    o.append(
        '<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" '
        'fill="none" stroke="{e}" stroke-width="{sw}" opacity="0.6"/>'.format(
            x=p(bx + 16), y=p(by + 16), w=p(bw - 26), h=p(bh - 26),
            r=p(21), e=BOARD_EDGE, sw=p(4))
    )
    # 顶部反光
    o.append(
        '<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" '
        'fill="url(#glare)"/>'.format(
            x=p(bx + 13), y=p(by + 13), w=p(bw - 26), h=p(bh * 0.36), r=p(19))
    )

    # 光标行的绿色底块，先画（在字下面）
    o.append(
        '<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" '
        'fill="{g}" opacity="0.24"/>'.format(
            x=p(bx + 26), y=p(by + 106), w=p(158), h=p(64),
            r=p(18), g=READ)
    )

    # 真实汉字：「你好」已读绿，「今天」光标白
    font = ('-apple-system,"PingFang SC","Hiragino Sans GB",'
            '"Heiti SC",sans-serif')
    o.append(
        '<text x="{x}" y="{y}" font-family=\'{f}\' font-size="{fs}" '
        'font-weight="700" fill="{c}" letter-spacing="{ls}">你好</text>'.format(
            x=p(bx + 40), y=p(by + 84), f=font, fs=p(64), c=READ, ls=p(2))
    )
    o.append(
        '<text x="{x}" y="{y}" font-family=\'{f}\' font-size="{fs}" '
        'font-weight="700" fill="{c}" letter-spacing="{ls}">今天</text>'.format(
            x=p(bx + 40), y=p(by + 158), f=font, fs=p(64), c=NOW, ls=p(2))
    )
    # 已读行后面跟一小段未读，暗示还有内容
    o.append(
        '<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" '
        'fill="#6B7484" opacity="0.85"/>'.format(
            x=p(bx + 196), y=p(by + 54), w=p(124), h=p(22), r=p(11))
    )

    o.append('</svg>')
    return '\n'.join(o)


if __name__ == '__main__':
    with open('icon.svg', 'w') as f:
        f.write(build())
    print('icon.svg 已生成')
