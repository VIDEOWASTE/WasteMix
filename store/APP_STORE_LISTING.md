# WasteMix — App Store Listing Copy

Paste-ready text for App Store Connect. Character limits noted; all fields below
are within Apple's limits.

---

## App Name (max 30)
```
WasteMix
```

## Subtitle (max 30)
```
Live 4-Channel Video Mixer
```
_(26 chars)_

## Promotional Text (max 170 — editable anytime without review)
```
Mix four live video channels in real time with NDI, GPU effects, audio-reactive visuals, and Resolume-style projection mapping. Built for VJs and live visual artists.
```

## Keywords (max 100, comma-separated, no spaces needed between terms)
```
VJ,video mixer,NDI,visuals,projection mapping,live,effects,crossfader,blend,strobe,audio reactive
```
_(Tip: don't repeat words already in the app name/subtitle; don't use spaces after commas — they waste characters.)_

## Support URL (required)
```
https://videowaste.github.io/WasteMix/support.html
```

## Marketing URL (optional)
```
https://videowaste.github.io/WasteMix/
```

## Privacy Policy URL (required)
```
https://videowaste.github.io/WasteMix/privacy.html
```

## Primary Category
```
Photo & Video
```
## Secondary Category (optional)
```
Music
```

---

## Description (max 4000)

```
WasteMix is a real-time, 4-channel video mixer built for VJs, live visual artists, and anyone performing visuals on stage. Mix cameras, video files, images, and NDI network sources together with a GPU-accelerated engine that runs at a smooth 60fps.

MIXER
• Four independent video channels with vertical faders
• 16 blend modes — Normal, Add, Multiply, Screen, Overlay, Difference and more
• A/B crossfader with Cut, Mix, Dip, and 8 directional wipe transitions
• Preview (PVW) and Program (PGM) monitors
• Tap-tempo BPM sync

EFFECTS
• 16+ real-time GPU effects: Mirror, Invert, Mosaic, Strobe, RGB Split, Posterize, Blur, Solarize, Edges, Datamosh, Scanlines, Kaleidoscope, Halftone, Feedback
• Per-channel freeze frame
• Luma key and chroma key
• Picture-in-Picture with scale and position
• Per-channel and global color correction — brightness, contrast, saturation, hue, RGB gain, lift

MODULATION
• LFO with sine, triangle, square, sawtooth, and random waveforms
• BPM-synced modulation
• Audio reactivity with a 7-band EQ, from Sub Bass to Brilliance
• Quick reactive presets: Kick, Bass, Vocal, Hats, Full

INPUT SOURCES
• iPad camera (front/back)
• NDI network sources with automatic discovery
• Video files (MP4, MOV, M4V)
• Images (JPG, PNG, HEIF)
• Solid colors and test patterns (Color Bars, Gradient, Checkerboard)

OUTPUT & PROJECTION MAPPING
• NDI output — global program feed plus per-screen sends
• External display output over HDMI / USB-C with fullscreen support
• Resolume-style Advanced Output:
   - Multi-screen, multi-slice output
   - Per-slice mesh warp with draggable grid nodes
   - Corner-pin perspective warping
   - Soft-edge blending for multi-projector setups
   - Free transform — move, resize, rotate

PRESETS
• Save and recall your full mixer state, including per-channel settings

Built with a Metal rendering pipeline and a liquid UI that scales to any screen. Whether you're running a single projector at a small show or a multi-display mapped setup, WasteMix keeps up.
```

---

## Notes / What you still need to supply

1. **Privacy Policy / Support / Marketing URLs:** hosted on GitHub Pages from
   `docs/` on `main`. If you edit `store/PRIVACY_POLICY.md`, update
   `docs/privacy.html` to match.
2. **Screenshots:** the existing captures in `~/Desktop/WasteMix-screens` show
   the camera permission alert — retake them with permissions already granted.
3. **Screenshots (required):** This is an iPad app, so you need **13-inch iPad**
   screenshots at **2048 × 2732** (portrait) or **2732 × 2048** (landscape),
   1–10 images. Capture from a real iPad or the iPad Pro simulator.
4. **Build:** Select build **1.0 (9)** (standard NDI SDK). Do not ship build 8.
5. **Age Rating:** Answer the questionnaire (WasteMix has no objectionable
   content → expect 4+).
6. **Copyright field:** e.g. `2026 Nathaniel Coleman`.
