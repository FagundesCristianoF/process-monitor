.PHONY: build run clean bundle release export notarize install uninstall identities dev

APP_NAME = Process Monitor
BUNDLE_NAME = ProcessMonitor.app
BUILD_DIR_DEBUG = .build/arm64-apple-macosx/debug
BUILD_DIR_RELEASE = .build/apple/Products/Release
EXPORT_DIR = export
TEAM_ID = VP83767PVX
XCSTRINGS = ProcessMonitor/Resources/Localizable.xcstrings
RESOURCE_BUNDLE = ProcessMonitor_ProcessMonitor.bundle

# Keychain profile name for notarytool (created via: xcrun notarytool store-credentials)
NOTARY_PROFILE ?= ProcessMonitor

# Signing identity. Override with: make export SIGN_IDENTITY="Developer ID Application: ..."
SIGN_IDENTITY ?= Developer ID Application

build:
	swift build

bundle: build
	rm -rf "$(BUNDLE_NAME)"
	mkdir -p "$(BUNDLE_NAME)/Contents/MacOS"
	mkdir -p "$(BUNDLE_NAME)/Contents/Resources"
	cp "$(BUILD_DIR_DEBUG)/ProcessMonitor" "$(BUNDLE_NAME)/Contents/MacOS/ProcessMonitor"
	cp Info.plist "$(BUNDLE_NAME)/Contents/Info.plist"
	cp -R "$(BUILD_DIR_DEBUG)/$(RESOURCE_BUNDLE)" "$(BUNDLE_NAME)/Contents/Resources/$(RESOURCE_BUNDLE)"
	rm -f "$(BUNDLE_NAME)/Contents/Resources/$(RESOURCE_BUNDLE)/Localizable.xcstrings"
	xcrun xcstringstool compile --output-directory "$(BUNDLE_NAME)/Contents/Resources" "$(XCSTRINGS)"
	codesign --force --deep --options runtime --sign "$(SIGN_IDENTITY)" --team-id "$(TEAM_ID)" "$(BUNDLE_NAME)"

run: bundle
	open "$(BUNDLE_NAME)"

release:
	swift build -c release --arch arm64 --arch x86_64

export: release
	rm -rf "$(EXPORT_DIR)" "$(BUNDLE_NAME)"
	mkdir -p "$(BUNDLE_NAME)/Contents/MacOS"
	mkdir -p "$(BUNDLE_NAME)/Contents/Resources"
	cp "$(BUILD_DIR_RELEASE)/ProcessMonitor" "$(BUNDLE_NAME)/Contents/MacOS/ProcessMonitor"
	cp Info.plist "$(BUNDLE_NAME)/Contents/Info.plist"
	cp -R "$(BUILD_DIR_RELEASE)/$(RESOURCE_BUNDLE)" "$(BUNDLE_NAME)/Contents/Resources/$(RESOURCE_BUNDLE)"
	rm -f "$(BUNDLE_NAME)/Contents/Resources/$(RESOURCE_BUNDLE)/Localizable.xcstrings"
	xcrun xcstringstool compile --output-directory "$(BUNDLE_NAME)/Contents/Resources" "$(XCSTRINGS)"
	strip "$(BUNDLE_NAME)/Contents/MacOS/ProcessMonitor"
	codesign --force --deep --options runtime --sign "$(SIGN_IDENTITY)" --team-id "$(TEAM_ID)" "$(BUNDLE_NAME)"
	mkdir -p "$(EXPORT_DIR)"
	ditto -c -k --keepParent "$(BUNDLE_NAME)" "$(EXPORT_DIR)/ProcessMonitor.zip"
	@echo ""
	@echo "Signed and zipped to $(EXPORT_DIR)/ProcessMonitor.zip"
	@echo "Run 'make notarize' to notarize it with Apple."

notarize:
	@test -f "$(EXPORT_DIR)/ProcessMonitor.zip" || (echo "Run 'make export' first." && exit 1)
	@echo "Submitting to Apple for notarization..."
	xcrun notarytool submit "$(EXPORT_DIR)/ProcessMonitor.zip" \
		--keychain-profile "$(NOTARY_PROFILE)" \
		--wait
	@echo ""
	@echo "Stapling notarization ticket to app..."
	xcrun stapler staple "$(BUNDLE_NAME)"
	@echo ""
	@echo "Re-zipping with stapled ticket..."
	rm -f "$(EXPORT_DIR)/ProcessMonitor.zip"
	ditto -c -k --keepParent "$(BUNDLE_NAME)" "$(EXPORT_DIR)/ProcessMonitor.zip"
	@echo ""
	@echo "Done! $(EXPORT_DIR)/ProcessMonitor.zip is signed + notarized."
	@echo "Recipients can open it without any Gatekeeper warnings."

INSTALL_DIR = /Applications

install:
	@if xcrun stapler validate "$(BUNDLE_NAME)" 2>/dev/null; then \
		echo "App is already signed and notarized. Skipping build."; \
	else \
		echo "App not notarized yet. Building, signing, and notarizing..."; \
		$(MAKE) export; \
		$(MAKE) notarize; \
	fi
	@echo ""
	@echo "Installing to $(INSTALL_DIR)/$(BUNDLE_NAME)..."
	@osascript -e 'tell application "Process Monitor" to quit' 2>/dev/null || true
	@sleep 1
	rm -rf "$(INSTALL_DIR)/$(BUNDLE_NAME)"
	cp -R "$(BUNDLE_NAME)" "$(INSTALL_DIR)/$(BUNDLE_NAME)"
	@echo "Installed. Launching..."
	open "$(INSTALL_DIR)/$(BUNDLE_NAME)"
	@echo ""
	@echo "Process Monitor is now installed in $(INSTALL_DIR)."

dev: export notarize
	@echo "==> Installing to $(INSTALL_DIR)/$(BUNDLE_NAME)..."
	@osascript -e 'tell application "Process Monitor" to quit' 2>/dev/null || true
	@sleep 1
	rm -rf "$(INSTALL_DIR)/$(BUNDLE_NAME)"
	cp -R "$(BUNDLE_NAME)" "$(INSTALL_DIR)/$(BUNDLE_NAME)"
	@echo "==> Launching..."
	open "$(INSTALL_DIR)/$(BUNDLE_NAME)"
	@echo ""
	@echo "Done. Process Monitor built, signed, notarized, and installed to $(INSTALL_DIR)."

uninstall:
	@osascript -e 'tell application "Process Monitor" to quit' 2>/dev/null || true
	@sleep 1
	rm -rf "$(INSTALL_DIR)/$(BUNDLE_NAME)"
	@echo "Process Monitor has been uninstalled."

identities:
	@echo "Available signing identities:"
	@security find-identity -v -p codesigning

clean:
	swift package clean
	rm -rf "$(BUNDLE_NAME)" "$(EXPORT_DIR)"
