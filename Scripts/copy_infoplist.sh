#!/bin/bash

# Script to ensure the correct Info.plist is used

# Ensure the target directory exists
mkdir -p "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}"

# Copy the custom Info.plist
cp "${SRCROOT}/Vocal/Info.plist" "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Info.plist"

# Convert to binary format
/usr/bin/plutil -convert binary1 "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Info.plist"

echo "Custom Info.plist copied to ${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Info.plist"
