APP_NAME := Chronicle REM
APP_DIR := $(HOME)/Applications/$(APP_NAME).app
ROOT := $(HOME)/.codex/memories/extensions/chronicle/persistent_detailed_only_use_when_summaries_not_enough

.PHONY: app package install archive timelapse clean

app:
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"
	./scripts/make_app_icon.sh "$(APP_DIR)/Contents/Resources/AppIcon.icns"
	swiftc src/ChronicleREM.swift -framework AppKit -framework SwiftUI -o "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"
	cp app/Info.plist "$(APP_DIR)/Contents/Info.plist"

package: app
	mkdir -p dist
	cd "$(HOME)/Applications" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$(APP_NAME).app" "$(CURDIR)/dist/Chronicle-REM.app.zip"

dmg:
	./scripts/package_release.sh

install:
	./scripts/install.sh

release:
	./scripts/package_release.sh

archive:
	./scripts/archive_chronicle.sh

timelapse:
	./scripts/make_timelapse.sh

clean:
	rm -rf dist
