# WasteMix — App Store Listing Copy

Paste-ready text for App Store Connect, audited against build 1.0 (11).
Character counts are exact; all fields are within Apple's limits.

## Name (8/30)
```
WasteMix
```

## Subtitle (26/30)
```
Live 4-Channel Video Mixer
```

## Primary category
```
Photo & Video
```

## Secondary category
```
Music
```
_Optional_

## Bundle ID
```
com.wastemix.app
```
_Pick this when creating the app record_

## SKU
```
wastemix-ipad
```
_Any unique string; only you see it_

## Promotional text (151/170)
```
Mix four live video channels in real time with NDI®, GPU effects, audio-reactive visuals and projection mapping. Built for VJs and live visual artists.
```
_Editable any time without a new review_

## Description (1631/4000)
```
WasteMix is a real-time, four-channel video mixer for iPad, built for VJs, live visual artists and anyone running visuals at a show. Mix cameras, video files, images, capture cards and NDI® network sources on a GPU engine that runs at 60 fps.

MIXER
• Four channels with faders, plus Preview (PVW) and Program (PGM) monitors
• 33 blend modes, including Screen, Add, Difference, Hard Mix and Glow
• A/B crossfader with multi-channel assignment
• Per-channel transitions: Mix, Cut, Dip to Black and 10 wipes
• Tap tempo, Fade to Black and Recall

EFFECTS
• 20 real-time GPU effects, including Kaleidoscope, Datamosh, Feedback, Mirror, Halftone, Scanlines, Thermal, Tunnel and Displace
• Freeze frame, luma key and chroma key
• Picture-in-picture with scale, position and rotation
• Per-channel and global color correction

MODULATION
• Per-channel LFOs and a master LFO: sine, triangle, square, sawtooth and random
• Audio reactivity with a 7-band EQ and quick presets for kick, bass, vocals and hats

SOURCES
• iPad cameras, plus USB and HDMI capture cards over USB-C
• NDI® sources on your network, found automatically
• Videos and images from Photos
• 15 audio visualizer styles
• Solid colors and test patterns

OUTPUT & PROJECTION MAPPING
• NDI® output of the program feed, plus per-screen sends
• External displays and projectors over USB-C or HDMI
• Advanced Output: multiple screens and slices, mesh warp, corner pin, soft-edge blending and free transform
• Record the program output to Photos

PRESETS
• Save and recall the full mixer state

No accounts, no tracking, no ads.

NDI® is a registered trademark of Vizrt NDI AB.
```

## Keywords (91/100)
```
VJ,visuals,NDI,projection mapping,live,effects,crossfader,blend,strobe,audio reactive,video
```
_Comma-separated, no spaces after commas_

## Support URL
```
https://videowaste.github.io/WasteMix/support.html
```

## Marketing URL
```
https://videowaste.github.io/WasteMix/
```
_Optional_

## Copyright
```
2026 Nathaniel Coleman
```

## Privacy Policy URL
```
https://videowaste.github.io/WasteMix/privacy.html
```

## Notes for App Review (1142/4000)
```
WasteMix is a live video mixer for VJs. No account or sign-in is required.

To see it working without extra equipment:
1. Tap SOURCE on channel 1 and pick Back Camera, a video or image from Photos, a Test Pattern or an Audio Visualizer. The fader rises automatically and the picture appears in the PGM monitor.
2. Add sources to more channels, raise their faders, and try the crossfader, blend modes (NORM menu), FX and PARAMS.
3. The red ADVANCED OUTPUT button in the MASTER section opens the projection-mapping window.

NDI: WasteMix sends and receives NDI® video over the local network, which is why it asks for Local Network access. To test it, run any NDI sender (for example the free NDI Tools from ndi.video) on a computer on the same Wi-Fi. It appears under SOURCE > NDI Network Sources. WasteMix's own output appears on the network as "WasteMix Program".

Permissions: Camera (camera sources), Microphone (audio-reactive visuals only; audio is never recorded), Photos (importing media and saving recordings), Local Network (NDI).

NDI® is a registered trademark of Vizrt NDI AB. WasteMix uses the NDI SDK for Apple under its license.
```

## Other answers

- **App Privacy:** No, we do not collect data from this app ("Data Not Collected"). No tracking.
- **Age rating:** None / No for every question → 4+.
- **Content rights:** does not contain, show or access third-party content.
- **Export compliance:** answered by `ITSAppUsesNonExemptEncryption = false` in Info.plist.
- **Build:** 1.0 (11). Never submit build 8 (unlicensed NDI Advanced SDK).
- **Sign-in required:** No.
- **Mac availability:** untick "Make this app available on Mac" until the Mac build is tested (needs App Sandbox).
- **Screenshots:** `~/Desktop/WasteMix-screens-v2`, iPad 13-inch slot (2064 × 2752), order 01–04. Regenerate in the Simulator with the Debug-only `-WMDemo <mixer|fx|advanced|color>` launch argument.
- **Your call:** price, and a phone number for the App Review contact.
