#!/usr/bin/env sh

set -e

mkdir -p Icon.iconset

sips -z 32 32     icon.png --out Icon.iconset/icon_16x16@2x.png   > /dev/null
sips -z 32 32     icon.png --out Icon.iconset/icon_32x32.png      > /dev/null
sips -z 64 64     icon.png --out Icon.iconset/icon_32x32@2x.png   > /dev/null
sips -z 128 128   icon.png --out Icon.iconset/icon_128x128.png    > /dev/null
sips -z 256 256   icon.png --out Icon.iconset/icon_128x128@2x.png > /dev/null
sips -z 256 256   icon.png --out Icon.iconset/icon_256x256.png    > /dev/null
sips -z 512 512   icon.png --out Icon.iconset/icon_256x256@2x.png > /dev/null
sips -z 512 512   icon.png --out Icon.iconset/icon_512x512.png    > /dev/null
sips -z 1024 1024 icon.png --out Icon.iconset/icon_512x512@2x.png > /dev/null
sips -z 1024 1024 icon.png --out Icon.iconset/icon_1024x1024.png  > /dev/null

iconutil -c icns Icon.iconset -o Icon.icns

rm -rf Icon.iconset

echo "Successfully generated Icon.icns"
