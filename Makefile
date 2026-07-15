# Makefile
APP_NAME    = OpenTab
BUNDLE_ID   = com.tburkhalterr.opentab
CONFIG      = release
BUILD_DIR   = .build/$(CONFIG)
APP_BUNDLE  = $(APP_NAME).app
CONTENTS    = $(APP_BUNDLE)/Contents

# A stable signing identity lets macOS remember the Accessibility grant across
# rebuilds. The self-signed dev cert is untrusted (CSSMERR_TP_NOT_TRUSTED), which
# codesign and TCC accept, so we match by hash without the `-v` (valid-only)
# filter and fall back to ad-hoc ("-") when it is absent. Create it with `make cert`.
# Sort so the same hash is chosen every build even if several "OpenTab Dev"
# certs exist and `find-identity` returns them in a non-deterministic order.
SIGN_ID := $(shell security find-identity -p codesigning 2>/dev/null | awk '/OpenTab Dev/{print $$2}' | sort | head -1)
ifeq ($(SIGN_ID),)
SIGN_ID := -
endif

.PHONY: all build test lint app sign run clean cert release notarize

all: app

build:
	swift build -c $(CONFIG)

test:
	swift test

# Style / correctness lint (brew install swiftlint). Enforced in CI.
lint:
	swiftlint lint --strict

app: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(CONTENTS)/MacOS/$(APP_NAME)"
	cp Info.plist "$(CONTENTS)/Info.plist"
	iconutil -c icns Resources/AppIcon.iconset -o "$(CONTENTS)/Resources/AppIcon.icns"
	cp Resources/menubar/MenubarIcon.png "$(CONTENTS)/Resources/MenubarIcon.png"
	cp Resources/menubar/MenubarIcon@2x.png "$(CONTENTS)/Resources/MenubarIcon@2x.png"
	$(MAKE) sign
	@echo "Built and signed $(APP_BUNDLE) with identity: $(SIGN_ID)"

sign:
	codesign --force --sign "$(SIGN_ID)" --identifier "$(BUNDLE_ID)" "$(APP_BUNDLE)"

run: app
	open "$(APP_BUNDLE)"

# One-time: create a self-signed code-signing certificate named "OpenTab Dev"
# so the Accessibility permission persists across rebuilds.
cert:
	./scripts/create-dev-cert.sh

# Build + zip the app and print the version/sha256 for the Homebrew cask.
release:
	./scripts/package-release.sh

# Sign (Developer ID), notarize, staple and zip a Gatekeeper-passing build.
# Requires DEV_ID and NOTARY_PROFILE env vars — see scripts/notarize-release.sh.
notarize:
	./scripts/notarize-release.sh

clean:
	rm -rf .build "$(APP_BUNDLE)"
