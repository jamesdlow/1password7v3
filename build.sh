#!/bin/sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHROME_DIR="$SCRIPT_DIR/chrome"
MANIFEST="$CHROME_DIR/manifest.json"

if [ ! -f "$MANIFEST" ]; then
	echo "Error: manifest not found at $MANIFEST" >&2
	exit 1
fi

VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MANIFEST" | head -n 1)"

if [ -z "$VERSION" ]; then
	echo "Error: could not parse version from $MANIFEST" >&2
	exit 1
fi

ZIP_NAME="1password7v3-$VERSION.zip"
ZIP_PATH="$SCRIPT_DIR/$ZIP_NAME"
CRX_NAME="1password7v3-$VERSION.crx"
CRX_PATH="$SCRIPT_DIR/$CRX_NAME"
CRX_KEY_PATH="${CRX_KEY_PATH:-$SCRIPT_DIR/1password7v3.pem}"
PACKED_CRX="$SCRIPT_DIR/chrome.crx"
PACKED_PEM="$SCRIPT_DIR/chrome.pem"

find_chrome_bin() {
	if [ -n "${CHROME_BIN:-}" ] && [ -x "$CHROME_BIN" ]; then
		echo "$CHROME_BIN"
		return 0
	fi

	for candidate in \
		"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
		"/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta" \
		"/Applications/Chromium.app/Contents/MacOS/Chromium"
	do
		if [ -x "$candidate" ]; then
			echo "$candidate"
			return 0
		fi
	done

	for cmd in google-chrome chromium chromium-browser; do
		if command -v "$cmd" >/dev/null 2>&1; then
			command -v "$cmd"
			return 0
		fi
	done

	return 1
}

CHROME_PACKER="$(find_chrome_bin || true)"

if [ -z "$CHROME_PACKER" ]; then
	echo "Error: could not find a Chrome/Chromium executable for --pack-extension" >&2
	echo "Set CHROME_BIN to the browser binary path and re-run." >&2
	exit 1
fi

rm -f "$ZIP_PATH"
rm -f "$CRX_PATH"

# Migrate legacy key name once, then always use CRX_KEY_PATH.
if [ ! -f "$CRX_KEY_PATH" ] && [ -f "$PACKED_PEM" ]; then
	mv "$PACKED_PEM" "$CRX_KEY_PATH"
fi

if [ ! -f "$CRX_KEY_PATH" ]; then
	openssl genrsa -out "$CRX_KEY_PATH" 2048 >/dev/null 2>&1
	echo "Generated signing key at $CRX_KEY_PATH"
fi

SIGNING_PUBLIC_KEY="$(openssl rsa -in "$CRX_KEY_PATH" -pubout -outform DER 2>/dev/null | openssl base64 -A)"

if [ -z "$SIGNING_PUBLIC_KEY" ]; then
	echo "Error: could not derive public key from $CRX_KEY_PATH" >&2
	exit 1
fi

# Keep manifest key aligned with signing key for deterministic extension IDs.
#awk -v key="$SIGNING_PUBLIC_KEY" '
#{
#	if ($0 ~ /"key"[[:space:]]*:/) {
#		sub(/"key"[[:space:]]*:[[:space:]]*"[^"]*",/, "\"key\": \"" key "\",")
#	}
#	print
#}
#' "$MANIFEST" > "$MANIFEST.tmp"
#mv "$MANIFEST.tmp" "$MANIFEST"

cd "$CHROME_DIR"
zip -r "$ZIP_PATH" . -x "*/.DS_Store" ".claude/*" "*/.claude/*"

# Chrome writes packed artifacts next to the extension directory, using its basename.
rm -f "$PACKED_CRX"
"$CHROME_PACKER" --pack-extension="$CHROME_DIR" --pack-extension-key="$CRX_KEY_PATH"

# Clean up any legacy key output name if Chrome writes one.
if [ -f "$PACKED_PEM" ] && [ "$PACKED_PEM" != "$CRX_KEY_PATH" ]; then
	rm -f "$PACKED_PEM"
fi

if [ ! -f "$PACKED_CRX" ]; then
	echo "Error: Chrome did not produce $PACKED_CRX" >&2
	exit 1
fi

mv "$PACKED_CRX" "$CRX_PATH"

echo "Created $ZIP_NAME"
echo "Created $CRX_NAME"