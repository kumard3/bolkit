#!/bin/sh
set -e
mkdir -p "$(dirname "$0")/SherpaKit/Vendor"
cd "$(dirname "$0")/SherpaKit/Vendor"
gh release download xcframework -R k2-fsa/sherpa-onnx -p 'sherpa-onnx-v2.0.1-ios-shared-onnxruntime-static.xcframework.zip' -O sherpa.zip --clobber
unzip -q -o sherpa.zip 'SherpaOnnxC.xcframework/*'
