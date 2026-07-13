# Makefile
APP_NAME    = OpenTab
BUNDLE_ID   = ch.socraft.opentab
CONFIG      = release
BUILD_DIR   = .build/$(CONFIG)
APP_BUNDLE  = $(APP_NAME).app
CONTENTS    = $(APP_BUNDLE)/Contents

.PHONY: all build app run clean

all: app

build:
	swift build -c $(CONFIG)

# Assemble a proper .app bundle so macOS can attach Accessibility permission to it.
app: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(CONTENTS)/MacOS/$(APP_NAME)"
	cp Info.plist "$(CONTENTS)/Info.plist"
	@echo "Built $(APP_BUNDLE)"

run: app
	open "$(APP_BUNDLE)"

clean:
	rm -rf .build "$(APP_BUNDLE)"
