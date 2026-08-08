#!/usr/bin/env python3
"""Export the Block Party mark: one vector source -> the three Xcode assets.

  AppIcon.png       1024x1024 RGB, full-bleed, no alpha (iOS applies its own mask)
  LaunchMark.png     880x880  RGB, the documented 72/1024 inset crop of the SAME pixels
  MarkTemplate.png   880x880  RGBA, alpha = artwork coverage, for tinted renderings

The template's alpha comes from a white-on-black silhouette render of the identical
element list — knockouts included — so the gap that separates the hat from the B stays
transparent and every edge keeps its antialiasing. Deriving it from an alpha render
instead would fuse the hat to the B, because the knockout only exists over the tile.

Also re-measures BlockPartyMark.contentFraction, which the brand skill requires
whenever the icon is re-exported.
"""
import json, os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
OUT = os.path.join(ROOT, 'build')
sys.path.insert(0, HERE)
import build

INSET = 72          # LaunchMark inset, in 1024-space units (documented contract)
ICON = 1024
CROP = ICON - 2 * INSET      # 880

# Bare monogram (Aug 8, Jesse's call): the script BP alone, no hat.
# 781 puts the lockup on exactly 780 px of the 880 LaunchMark, which keeps
# contentFraction at the 0.8864 already in LoaderBlockPartyMark.swift.
HAT = False
FINAL = dict(letters_w=781.0, stripe_frac=0.62)
PALETTE = dict(tile='#111111', accent='#FA5A34',
               hat_body='#FAFAF7', hat_strip='#FA5A34', pompom='#FA5A34')


def sh(*a):
    r = subprocess.run(a, capture_output=True, text=True, cwd=ROOT)
    if r.returncode:
        raise SystemExit(f'FAILED: {" ".join(a)}\n{r.stderr}')
    return r.stdout


def main():
    os.makedirs(OUT, exist_ok=True)
    L = dict(build.L); L.update(FINAL)

    # 1. The vector source of truth.
    P = dict(build.P); P.update(PALETTE)
    svg, info = build.build(P=P, L=L, hat=HAT)
    svg_path = os.path.join(OUT, 'block-party-mark.svg')
    open(svg_path, 'w').write(svg)
    print(f'vector source      -> {svg_path}')

    # 2. AppIcon: full-bleed, no alpha.
    icon = os.path.join(OUT, 'AppIcon.png')
    sh('swift', os.path.join(HERE, 'render.swift'), svg_path, icon, str(ICON))

    # 3. LaunchMark: the 72/1024 inset crop of those same pixels.
    launch = os.path.join(OUT, 'LaunchMark.png')
    sh('swift', os.path.join(HERE, 'crop.swift'), icon, launch, str(INSET), str(INSET), str(CROP), str(CROP), str(CROP))

    # 4. MarkTemplate: white-on-black silhouette -> alpha, same crop.
    sil = dict(P)
    sil.update(tile='#000000', accent='#FFFFFF', hat_body='#FFFFFF',
               hat_strip='#FFFFFF', pompom='#FFFFFF')
    sil_svg, _ = build.build(P=sil, L=L, hat=HAT)
    sil_path = os.path.join(OUT, '_silhouette.svg')
    open(sil_path, 'w').write(sil_svg)
    sil_png = os.path.join(OUT, '_silhouette.png')
    sh('swift', os.path.join(HERE, 'render.swift'), sil_path, sil_png, str(ICON))
    tmpl = os.path.join(OUT, 'MarkTemplate.png')
    sh('swift', os.path.join(HERE, 'template.swift'), sil_png, tmpl, str(INSET), str(CROP))

    # 5. Re-measure contentFraction off LaunchMark, exactly as the code comment defines
    #    it: the BP lockup's extent as a fraction of the asset's side.
    m = json.loads(sh('swift', os.path.join(HERE, 'measure.swift'), launch, '--not', PALETTE['tile'], '--tol', '24'))
    cf = m['long_side'] / CROP
    print(f"\nlockup in LaunchMark: {m['bbox_size'][0]}x{m['bbox_size'][1]} px of {CROP}")
    print(f"contentFraction     = {cf:.4f}   (was 0.8273)")

    icon_m = json.loads(sh('swift', os.path.join(HERE, 'measure.swift'), icon, '--not', PALETTE['tile'], '--tol', '24'))
    print(f"lockup on the tile  = {icon_m['content_fraction']:.4f} of 1024")
    print(f"off-centre          = dx {icon_m['dx_to_center']:.1f}, dy {icon_m['dy_to_center']:.1f} px")

    os.remove(sil_path); os.remove(sil_png)
    json.dump({'contentFraction': round(cf, 4), 'palette': PALETTE, 'layout': FINAL,
               'lockup_px_in_launchmark': m['bbox_size'], 'inset': INSET},
              open(os.path.join(OUT, 'mark.json'), 'w'), indent=2)
    print(f'\nassets in {OUT}')
    for f in sorted(os.listdir(OUT)):
        print(f'  {f:26} {os.path.getsize(os.path.join(OUT, f)):>9,} bytes')


if __name__ == '__main__':
    main()
