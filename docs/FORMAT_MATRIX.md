# Format capability matrix

**Generated from the running code** on the development machine (macOS 15.7.3,
arm64) via `swift run conv3rt --dump-matrix`. Do not edit by hand — regenerate.

- **Read / Write** come from the live Image I/O probe on this machine, plus any
  bundled codec (WebP write via libwebp).
- **Alpha / Anim / Pages / Metadata / Lossless** are the format's *capabilities*;
  a lossless path still depends on the source (see `LOSSLESS.md`).
- **Provider** is who decodes/encodes (`imageIO`, `pdfKit`, `bundled`, `builtin`).
- **Evidence** is how strongly the claim is backed: `tested`, `verified`,
  `documented`, `unverified`.

> Note: `Read == yes, Write == —` means the format can be used as a source but is
> **not** offered as an output target. This is real, not a bug.

| Format | UTI | Read | Write | Alpha | Anim | Pages | Metadata | Lossless | Provider | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|
| Adobe raw image | `com.adobe.raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| ASTC textures | `org.khronos.astc` | yes | yes | — | — | — | — | — | imageIO | documented |
| AVIF | `public.avif` | yes | — | yes | yes | — | yes | — | imageIO | unverified |
| BMP | `com.microsoft.bmp` | yes | yes | yes | — | — | — | yes | imageIO | verified |
| Camera RAW | `public.camera-raw-image` | yes | — | — | — | — | yes | — | imageIO | unverified |
| Canon CR2 raw image | `com.canon.cr2-raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Canon CR3 raw image | `com.canon.cr3-raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Canon CRW raw image | `com.canon.crw-raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Canon TIF raw image | `com.canon.tif-raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| com.apple.atx | `com.apple.atx` | yes | yes | — | — | — | — | — | imageIO | documented |
| com.microsoft.cur | `com.microsoft.cur` | yes | — | — | — | — | — | — | imageIO | documented |
| DDS | `com.microsoft.dds` | yes | yes | yes | — | — | — | — | imageIO | unverified |
| DxO raw image | `com.dxo.raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Epson raw image | `com.epson.raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Fuji raw image | `com.fuji.raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| GIF | `com.compuserve.gif` | yes | yes | yes | yes | — | yes | yes | imageIO | documented |
| Hasselblad 3FR raw image | `com.hasselblad.3fr-raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Hasselblad FFF raw image | `com.hasselblad.fff-raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| HEIC / HEIF | `public.heic` | yes | yes | yes | yes | — | yes | — | imageIO | documented |
| HEIF Image | `public.avci` | yes | — | — | — | — | — | — | imageIO | documented |
| HEIF Image | `public.heif` | yes | — | — | — | — | — | — | imageIO | documented |
| HEIF Image Sequence | `public.heics` | yes | yes | — | — | — | — | — | imageIO | documented |
| ICNS | `com.apple.icns` | yes | yes | yes | — | yes | — | yes | imageIO | documented |
| ICO | `com.microsoft.ico` | yes | yes | yes | — | yes | — | yes | imageIO | documented |
| JPEG | `public.jpeg` | yes | yes | — | — | — | yes | — | imageIO | documented |
| JPEG 2000 | `public.jpeg-2000` | yes | yes | yes | — | — | yes | yes | imageIO | documented |
| JPEG XL | `public.jpeg-xl` | yes | — | yes | yes | — | yes | yes | imageIO | unverified |
| Kodak raw image | `com.kodak.raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| KTX textures | `org.khronos.ktx` | yes | yes | — | — | — | — | — | imageIO | documented |
| Leaf raw image | `com.leafamerica.raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Leica raw image | `com.leica.rwl-raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Leica raw image | `com.leica.raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Minolta raw image | `com.konicaminolta.raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Multiple Picture Object image | `public.mpo-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Netpbm (PBM/PGM/PPM) | `public.pbm` | yes | yes | — | — | — | — | yes | imageIO | unverified |
| Nikon NRW raw image | `com.nikon.nrw-raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Nikon raw image | `com.nikon.raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Nikon raw image | `com.nikon.nefx-raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Olympus OR raw image | `com.olympus.or-raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Olympus raw image | `com.olympus.raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Olympus SR raw image | `com.olympus.sr-raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| OpenEXR | `com.ilm.openexr-image` | yes | yes | yes | — | — | yes | yes | imageIO | documented |
| org.khronos.ktx2 | `org.khronos.ktx2` | yes | yes | — | — | — | — | — | imageIO | documented |
| Panasonic raw 2 image | `com.panasonic.rw2-raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Panasonic raw image | `com.panasonic.raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| PDF | `com.adobe.pdf` | yes | yes | yes | — | yes | yes | — | pdfKit | unverified |
| Pentax raw image | `com.pentax.raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Phase One raw image | `com.phaseone.raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Photoshop (PSD) | `com.adobe.photoshop-image` | yes | yes | yes | — | — | — | — | imageIO | documented |
| PICT | `com.apple.pict` | yes | — | yes | — | — | — | — | imageIO | documented |
| PNG | `public.png` | yes | yes | yes | — | — | yes | yes | imageIO | tested |
| public.avis | `public.avis` | yes | — | — | — | — | — | — | imageIO | documented |
| PVRTC Textures | `public.pvr` | yes | yes | — | — | — | — | — | imageIO | documented |
| Radiance HDR | `public.radiance` | yes | — | — | — | — | — | — | imageIO | documented |
| Samsung raw image | `com.samsung.raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| SGI | `com.sgi.sgi-image` | yes | — | yes | — | — | — | yes | imageIO | unverified |
| Sony ARW raw image | `com.sony.arw-raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Sony AXR raw image | `com.sony.axr-raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Sony raw image | `com.sony.raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| Sony SR2 raw image | `com.sony.sr2-raw-image` | yes | — | — | — | — | — | — | imageIO | documented |
| SVG (vector) | `public.svg-image` | yes | — | yes | — | — | — | — | bundled | verified |
| TGA | `com.truevision.tga-image` | yes | yes | yes | — | — | — | yes | imageIO | documented |
| TIFF | `public.tiff` | yes | yes | yes | — | yes | yes | yes | imageIO | tested |
| WebP | `org.webmproject.webp` | yes | yes | yes | — | — | — | yes | imageIO | verified |
