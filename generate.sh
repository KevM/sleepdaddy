#!/bin/bash
set -e

echo "Generating Xcode project using XcodeGen..."
xcodegen generate
echo "Xcode project generation complete."
