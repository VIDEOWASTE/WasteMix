#!/bin/zsh
# Regenerates the App Store screenshots in the iPad Pro 13-inch Simulator.
#
#   tools/screenshots/shoot.sh <simulator-udid>
#
# Builds a Debug app (the -WMDemo launch argument only exists in Debug),
# renders four 1920x1080 source images, stages each scene from a clean
# install, and writes alpha-free 2064x2752 PNGs to store/screenshots/.
set -e
SIM=${1:?usage: shoot.sh <simulator-udid>}
ROOT=${0:A:h:h:h}
WORK=$(mktemp -d)
OUT=$ROOT/store/screenshots

xcrun simctl boot $SIM 2>/dev/null || true
xcrun simctl bootstatus $SIM >/dev/null
xcodebuild -project $ROOT/QuadMix/QuadMix.xcodeproj -scheme QuadMix -configuration Debug \
  -destination "id=$SIM" -derivedDataPath $WORK/dd build -quiet
APP=$WORK/dd/Build/Products/Debug-iphonesimulator/WasteMix.app

(cd $WORK && clang++ -O2 $ROOT/tools/screenshots/frames.cpp -o frames && ./frames)
for i in 1 2 3 4; do sips -s format png $WORK/demo$i.ppm --out $WORK/demo$i.png >/dev/null; done

shoot() { # scene outname
  xcrun simctl terminate $SIM com.wastemix.app 2>/dev/null || true
  xcrun simctl uninstall $SIM com.wastemix.app
  xcrun simctl install $SIM $APP
  xcrun simctl privacy $SIM grant all com.wastemix.app
  local DATA=$(xcrun simctl get_app_container $SIM com.wastemix.app data)
  mkdir -p "$DATA/Documents"
  cp $WORK/demo1.png "$DATA/Documents/Plasma.png"
  cp $WORK/demo2.png "$DATA/Documents/Neon Rings.png"
  cp $WORK/demo3.png "$DATA/Documents/Stripes.png"
  cp $WORK/demo4.png "$DATA/Documents/Sunset Tunnel.png"
  xcrun simctl launch $SIM com.wastemix.app -WMDemo $1 >/dev/null
  sleep 10
  xcrun simctl io $SIM screenshot $OUT/$2.png >/dev/null
}
shoot mixer 01-mixer
shoot fx 02-effects
shoot advanced 03-advanced-output
shoot color 04-color

# App Store Connect rejects screenshots with an alpha channel.
swift $ROOT/tools/screenshots/flatten.swift $OUT/0*.png
