VERSION ?= 0.0.0-dev

DIST  := dist
APP   := $(DIST)/PingMenubar.app
ICONS := $(DIST)/PingMenubar.iconset
ZIP   := $(DIST)/PingMenubar-$(VERSION).zip
LINT  := --recursive --configuration .swift-format app/Sources app/Tests

ifneq ($(shell xcodebuild -version 2>/dev/null),)
ARCH    := --arch arm64 --arch x86_64
RELEASE := app/.build/apple/Products/Release
else
ARCH    :=
RELEASE := app/.build/release
endif

.PHONY: build test fmt check app verify-app run clean

build:
	swift build --package-path app

test:
	swift run --package-path app PingMenubarTests

fmt:
	swift format --in-place $(LINT)

check:
	swift format lint --strict $(LINT)
	$(MAKE) test

app:
	rm -rf $(APP) $(ICONS)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	swift build --package-path app -c release $(ARCH) --product PingMenubar
	swift build --package-path app -c release --product IconExport
	cp $(RELEASE)/PingMenubar $(APP)/Contents/MacOS/PingMenubar
	app/.build/release/IconExport $(ICONS)
	iconutil -c icns -o $(APP)/Contents/Resources/PingMenubar.icns $(ICONS)
	sed 's/__VERSION__/$(VERSION)/g' packaging/Info.plist > $(APP)/Contents/Info.plist
	codesign --force --deep --sign - $(APP)
	rm -f $(ZIP)
	cd $(DIST) && ditto -c -k --keepParent PingMenubar.app $(notdir $(ZIP))
	shasum -a 256 $(ZIP)

verify-app:
	test -s $(APP)/Contents/Resources/PingMenubar.icns
	test -s $(APP)/Contents/Info.plist
	test -x $(APP)/Contents/MacOS/PingMenubar
	codesign --verify --deep --strict $(APP)
	lipo -archs $(APP)/Contents/MacOS/PingMenubar

run: app
	open $(APP)

clean:
	rm -rf $(DIST)
