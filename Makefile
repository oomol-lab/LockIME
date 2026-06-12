SCHEME      := LockIME
CONFIG      ?= Debug
# We ship one app per architecture (no universal binaries — download size).
# `make build ARCH=x86_64` cross-builds the Intel app (via the generic
# destination — `arch=x86_64` is not a valid destination on Apple Silicon);
# the result runs locally under Rosetta. Tests always run on the host arch.
ARCH        ?= arm64
DERIVED     := build/DerivedData
ifeq ($(CONFIG),Debug)
APP_NAME    := LockIME Dev
else
APP_NAME    := LockIME
endif
ifeq ($(ARCH),arm64)
DEST        := platform=macOS,arch=arm64
ARCHFLAGS   := ARCHS=arm64
else
DEST        := generic/platform=macOS
ARCHFLAGS   := ARCHS=$(ARCH) ONLY_ACTIVE_ARCH=NO
endif
APP         := $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app
DMG         := build/dmg/LockIME.dmg
XCB         := set -o pipefail && xcodebuild
PRETTY      := | xcbeautify

.PHONY: gen build run test archive dmg clean kill \
	update-test-none update-test-download-fail update-test-extract-fail \
	update-test-success update-test-stop

## Regenerate the Xcode project from project.yml
gen:
	xcodegen generate

## Build the app (Debug by default; ARCH=x86_64 for the Intel app)
build: gen
	$(XCB) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) -destination '$(DEST)' \
		$(ARCHFLAGS) build $(PRETTY)

## Build and launch the app
run: build
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@i=0; while pgrep -x "$(APP_NAME)" >/dev/null && [ $$i -lt 50 ]; do sleep 0.1; i=$$((i+1)); done
	open "$(APP)"

## Run the unit tests (hardware-touching suites skipped)
test: gen
	$(XCB) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) -destination '$(DEST)' test $(PRETTY)

## Run ALL tests including hardware suites (briefly switches the input source)
test-hw: gen
	@touch /tmp/lockime_hw_tests
	@$(XCB) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) -destination '$(DEST)' test $(PRETTY); \
		status=$$?; rm -f /tmp/lockime_hw_tests; exit $$status

## Build a Release archive (Developer ID)
archive: gen
	$(XCB) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) -destination 'generic/platform=macOS' \
		-archivePath build/LockIME.xcarchive archive $(PRETTY)

## Package the built app into a drag-to-install .dmg (CONFIG=Release for a
## release-config bundle; the image is unsigned/unnotarized — CI handles that)
dmg: build
	scripts/make-dmg.sh "$(APP)" "$(DMG)"

## Terminate a running instance
kill:
	@pkill -x "$(APP_NAME)" 2>/dev/null || true

# ——— Update lab: exercise the Sparkle update flows against a local feed ———
# (see scripts/update-lab/; each scenario rebuilds, relaunches, and prints
# what to expect. `make update-test-stop` tears everything down.)
UPDATE_LAB := scripts/update-lab/update-lab.sh

## Update lab: "You're up to date." (feed advertises the running version)
update-test-none: build
	@UPDATE_LAB_APP="$(APP)" $(UPDATE_LAB) none

## Update lab: download dies mid-transfer → download-failed error
update-test-download-fail: build
	@UPDATE_LAB_APP="$(APP)" $(UPDATE_LAB) download-fail

## Update lab: archive is signed but corrupt → extraction fails
update-test-extract-fail: build
	@UPDATE_LAB_APP="$(APP)" $(UPDATE_LAB) extract-fail

## Update lab: real end-to-end update — download, install, relaunch as 99.0.0
update-test-success: build
	@UPDATE_LAB_APP="$(APP)" $(UPDATE_LAB) success

## Update lab: stop the feed server and the app under test
update-test-stop:
	@$(UPDATE_LAB) stop

## Remove generated project and build artifacts
clean:
	rm -rf build LockIME.xcodeproj
