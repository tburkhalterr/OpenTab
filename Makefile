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
