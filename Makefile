.PHONY: build run clean bundle release export notarize appcast install uninstall identities dev

APP_NAME = Process Monitor
BUNDLE_NAME = ProcessMonitor.app
BUILD_DIR_DEBUG = .build/arm64-apple-macosx/debug
BUILD_DIR_RELEASE = .build/apple/Products/Release
EXPORT_DIR = export
TEAM_ID = VP83767PVX
XCSTRINGS = ProcessMonitor/Resources/Localizable.xcstrings
RESOURCE_BUNDLE = ProcessMonitor_ProcessMonitor.bundle
# Sparkle framework source (resolved by `swift build`). Verify with:
#   find .build/artifacts -name Sparkle.framework -type d
SPARKLE_FRAMEWORK = .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
# Framework version dir letter (e.g. B), derived so a Sparkle bump can't break signing paths.
SPARKLE_VER = $(shell readlink "$(SPARKLE_FRAMEWORK)/Versions/Current" 2>/dev/null)
# generate_appcast lives alongside generate_keys in the Sparkle artifact bin dir.
# Verify with: find .build/artifacts -name generate_appcast -type f
GENERATE_APPCAST = $(shell find .build/artifacts -name generate_appcast -type f | head -1)

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
	cp ProcessMonitor/Resources/AppIcon.icns "$(BUNDLE_NAME)/Contents/Resources/AppIcon.icns"
	rm -f "$(BUNDLE_NAME)/Contents/Resources/$(RESOURCE_BUNDLE)/Localizable.xcstrings"
	xcrun xcstringstool compile --output-directory "$(BUNDLE_NAME)/Contents/Resources" "$(XCSTRINGS)"
	mkdir -p "$(BUNDLE_NAME)/Contents/Frameworks"
	cp -R "$(SPARKLE_FRAMEWORK)" "$(BUNDLE_NAME)/Contents/Frameworks/Sparkle.framework"
	codesign --force --deep --options runtime --sign "$(SIGN_IDENTITY)" --team-id "$(TEAM_ID)" "$(BUNDLE_NAME)"

run: bundle
	open "$(BUNDLE_NAME)"

release:
	swift build -c release --arch arm64 --arch x86_64

export: release
	@test -n "$(SPARKLE_VER)" || (echo "SPARKLE_VER empty (Sparkle.framework not resolved); run 'swift build' first." && exit 1)
	rm -rf "$(EXPORT_DIR)" "$(BUNDLE_NAME)"
	mkdir -p "$(BUNDLE_NAME)/Contents/MacOS"
	mkdir -p "$(BUNDLE_NAME)/Contents/Resources"
	cp "$(BUILD_DIR_RELEASE)/ProcessMonitor" "$(BUNDLE_NAME)/Contents/MacOS/ProcessMonitor"
	cp Info.plist "$(BUNDLE_NAME)/Contents/Info.plist"
	cp -R "$(BUILD_DIR_RELEASE)/$(RESOURCE_BUNDLE)" "$(BUNDLE_NAME)/Contents/Resources/$(RESOURCE_BUNDLE)"
	cp ProcessMonitor/Resources/AppIcon.icns "$(BUNDLE_NAME)/Contents/Resources/AppIcon.icns"
	rm -f "$(BUNDLE_NAME)/Contents/Resources/$(RESOURCE_BUNDLE)/Localizable.xcstrings"
	xcrun xcstringstool compile --output-directory "$(BUNDLE_NAME)/Contents/Resources" "$(XCSTRINGS)"
	strip "$(BUNDLE_NAME)/Contents/MacOS/ProcessMonitor"
	mkdir -p "$(BUNDLE_NAME)/Contents/Frameworks"
	cp -R "$(SPARKLE_FRAMEWORK)" "$(BUNDLE_NAME)/Contents/Frameworks/Sparkle.framework"
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" --team-id "$(TEAM_ID)" \
		"$(BUNDLE_NAME)/Contents/Frameworks/Sparkle.framework/Versions/$(SPARKLE_VER)/XPCServices/Installer.xpc"
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" --team-id "$(TEAM_ID)" \
		"$(BUNDLE_NAME)/Contents/Frameworks/Sparkle.framework/Versions/$(SPARKLE_VER)/XPCServices/Downloader.xpc"
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" --team-id "$(TEAM_ID)" \
		"$(BUNDLE_NAME)/Contents/Frameworks/Sparkle.framework/Versions/$(SPARKLE_VER)/Autoupdate"
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" --team-id "$(TEAM_ID)" \
		"$(BUNDLE_NAME)/Contents/Frameworks/Sparkle.framework/Versions/$(SPARKLE_VER)/Updater.app"
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" --team-id "$(TEAM_ID)" \
		"$(BUNDLE_NAME)/Contents/Frameworks/Sparkle.framework"
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" --team-id "$(TEAM_ID)" "$(BUNDLE_NAME)"
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

appcast:
	@test -f "$(EXPORT_DIR)/ProcessMonitor.zip" || (echo "Run 'make export && make notarize' first." && exit 1)
	@test -n "$(GENERATE_APPCAST)" || (echo "generate_appcast not found; run 'swift build' first." && exit 1)
	@echo "Generating signed appcast.xml from $(EXPORT_DIR)/ProcessMonitor.zip..."
	"$(GENERATE_APPCAST)" "$(EXPORT_DIR)"
	@echo ""
	@echo "Done. Upload these to the GitHub release:"
	@echo "  $(EXPORT_DIR)/ProcessMonitor.zip"
	@echo "  $(EXPORT_DIR)/appcast.xml"

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
