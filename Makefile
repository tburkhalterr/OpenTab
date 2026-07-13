# Makefile
APP_NAME    = OpenTab
BUNDLE_ID   = com.tburkhalterr.opentab
CONFIG      = release
BUILD_DIR   = .build/$(CONFIG)
APP_BUNDLE  = $(APP_NAME).app
CONTENTS    = $(APP_BUNDLE)/Contents

# A stable signing identity lets macOS remember the Accessibility grant across
# rebuilds. Falls back to ad-hoc ("-") if the dev cert is absent (grant resets
# each build in that case). Create the cert once with `make cert`.
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q "OpenTab Dev" && echo "OpenTab Dev" || echo "-")

.PHONY: all build app sign run clean cert

all: app

build:
	swift build -c $(CONFIG)

app: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(CONTENTS)/MacOS/$(APP_NAME)"
	cp Info.plist "$(CONTENTS)/Info.plist"
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

clean:
	rm -rf .build "$(APP_BUNDLE)"
