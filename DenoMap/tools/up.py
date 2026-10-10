"""Shared pieces: read tiles, stitch, upscale 4x on the GPU, write DXT BLP."""
import json, os, struct, numpy as np, torch
from PIL import Image
import etcpak

JOBS = None
def tile(fid): return Image.open(f'raw/{fid}.blp').convert('RGBA')

def stitch(tiles):
    """tiles: [row, col, fid]. Returns one RGBA image, tiles laid out on a 256 grid."""
    ims = {(r, c): tile(f) for r, c, f in tiles}
    rows = max(r for r, c in ims) + 1; cols = max(c for r, c in ims) + 1
    out = Image.new('RGBA', (cols * 256, rows * 256), (0, 0, 0, 0))
    for (r, c), im in ims.items(): out.paste(im, (c * 256, r * 256))
    return out

_models = {}
def model(path):
    if path not in _models:
        from spandrel import ModelLoader
        m = ModelLoader().load_from_file(path)
        m = m.cuda().eval()
        try: m = m.half(); dt = torch.float16
        except Exception: dt = torch.float32
        _models[path] = (m, dt)
    return _models[path]

@torch.inference_mode()
def upscale_rgb(rgb, path, tile_px=384, pad=48):
    """rgb: HxWx3 uint8 -> 4x, tiled with overlap so no seams."""
    m, dt = model(path); s = 4
    h, w, _ = rgb.shape
    src = torch.from_numpy(np.ascontiguousarray(rgb)).cuda().permute(2, 0, 1).to(dt).div(255).unsqueeze(0)
    src = torch.nn.functional.pad(src, (pad, pad, pad, pad), mode='reflect')
    out = torch.zeros((3, h * s, w * s), dtype=dt, device='cuda')
    for y in range(0, h, tile_px):
        for x in range(0, w, tile_px):
            th, tw = min(tile_px, h - y), min(tile_px, w - x)
            piece = src[:, :, y:y + th + 2 * pad, x:x + tw + 2 * pad]
            up = m(piece)[0].clone()
            out[:, y * s:(y + th) * s, x * s:(x + tw) * s] = up[:, pad * s:(pad + th) * s, pad * s:(pad + tw) * s]
    res = (out.clamp(0, 1) * 255).round().byte().permute(1, 2, 0).cpu().numpy()
    del out, src
    torch.cuda.empty_cache()
    return res

def bleed(rgba, rounds=24):
    """Spread colour from visible pixels into transparent ones, so upscaling an
    overlay does not pull black into its soft edge."""
    a = rgba[..., 3].astype(np.float32) / 255
    rgb = rgba[..., :3].astype(np.float32) * a[..., None]
    w = a.copy()
    for _ in range(rounds):
        nrgb = rgb.copy(); nw = w.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            nrgb += np.roll(rgb, (dy, dx), (0, 1)); nw += np.roll(w, (dy, dx), (0, 1))
        hole = w < 1e-4
        rgb[hole] = nrgb[hole]; w[hole] = nw[hole]
        known = w > 1e-4
        # normalise the freshly filled pixels to full weight
        rgb[hole & known] /= w[hole & known][..., None]; w[hole & known] = 1
    out = np.where(w[..., None] > 1e-4, rgb / np.maximum(w[..., None], 1e-4), 0)
    src = rgba[..., :3].astype(np.float32)
    keep = (a > 0.999)[..., None]
    return np.where(keep, src, out).clip(0, 255).astype(np.uint8)

def write_blp(path, rgba, alpha):
    """BLP2, DXT1 (no alpha) or DXT5, full mip chain. rgba: HxWx4 uint8, power-of-two sides."""
    h, w, _ = rgba.shape
    mips = []; im = Image.fromarray(rgba, 'RGBA')
    while True:
        mw, mh = im.size
        pw, ph = max(4, mw), max(4, mh)
        src = im if (pw, ph) == (mw, mh) else im.resize((pw, ph), Image.BILINEAR)
        raw = src.tobytes()
        mips.append(etcpak.compress_bc3(raw, pw, ph) if alpha else etcpak.compress_bc1(raw, pw, ph))
        if mw == 1 and mh == 1: break
        im = im.resize((max(1, mw // 2), max(1, mh // 2)), Image.LANCZOS)
    head = struct.pack('<4sIBBBBII', b'BLP2', 1, 2, 8 if alpha else 0, 7 if alpha else 0, 1, w, h)
    offs = [0] * 16; sizes = [0] * 16; pos = 148 + 1024
    for i, m in enumerate(mips[:16]):
        offs[i] = pos; sizes[i] = len(m); pos += len(m)
    with open(path + '.tmp', 'wb') as f:
        f.write(head + struct.pack('<16I', *offs) + struct.pack('<16I', *sizes) + b'\0' * 1024)
        for m in mips[:16]: f.write(m)
    os.replace(path + '.tmp', path)


# ---- grain (added 2026-10-10) ------------------------------------------------------------
# RealESRGAN gives clean edges but wipes out the fine texture of the game art: a tile shrunk
# back to the size of the game file kept 21 to 27 percent of the fine detail of that file
# (measured), so the minimap and the maps looked flat and soft next to the originals. The
# texture of the source is therefore laid back over the upscale: what a slight blur removes
# from the source, enlarged with the picture.
def grain(src_rgb, sigma=1.0):
    from PIL import ImageFilter
    im = Image.fromarray(np.ascontiguousarray(src_rgb[..., :3]))
    return np.asarray(im, np.float32) - np.asarray(im.filter(ImageFilter.GaussianBlur(sigma)), np.float32)


def with_grain(up_rgb, src_rgb, amount=1.0, sigma=1.0):
    """up_rgb: the 4x upscale of src_rgb (same framing). Returns it with the source texture on top."""
    g = grain(src_rgb, sigma)
    h, w = up_rgb.shape[:2]
    big = np.stack([np.asarray(Image.fromarray(np.ascontiguousarray(g[..., c]), "F").resize((w, h), Image.BICUBIC))
                    for c in range(3)], -1)
    return np.clip(up_rgb[..., :3].astype(np.float32) + amount * big + 0.5, 0, 255).astype(np.uint8)
