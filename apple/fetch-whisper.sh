#!/bin/sh
set -e
cd "$(dirname "$0")/BolkitCore/Vendor" 2>/dev/null || { mkdir -p "$(dirname "$0")/BolkitCore/Vendor"; cd "$(dirname "$0")/BolkitCore/Vendor"; }
gh release download b5454 -R ggml-org/whisper.cpp -p '*xcframework.zip' -O w.zip --clobber
unzip -q -o w.zip 'build-apple/whisper.xcframework/*'
rm -rf whisper.xcframework && mv build-apple/whisper.xcframework . && rm -rf build-apple w.zip
