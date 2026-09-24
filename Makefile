APP := build/Mouse Shaker.app
BUNDLE_ID := dev.dumorro.mouseshaker

# With Command Line Tools only (no Xcode), swift-testing ships in the CLT but is not on the
# default search paths. With Xcode selected, SwiftPM finds it on its own.
DEVELOPER_DIR := $(shell xcode-select -p)
ifneq (,$(findstring CommandLineTools,$(DEVELOPER_DIR)))
  CLT_FW := $(DEVELOPER_DIR)/Library/Developer/Frameworks
  CLT_LIB := $(DEVELOPER_DIR)/Library/Developer/usr/lib
  TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_FW) -Xlinker -F -Xlinker $(CLT_FW) \
                -Xlinker -rpath -Xlinker $(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_LIB)
endif

.PHONY: build test app run install reset-perms logs clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

app:
	./scripts/build-app.sh

run: app
	-pkill -x MouseShaker
	open "$(APP)"

install: app
	-pkill -x MouseShaker
	rm -rf "/Applications/Mouse Shaker.app"
	cp -R "$(APP)" /Applications/
	open "/Applications/Mouse Shaker.app"

# Ad-hoc signatures change on every build, which silently invalidates the Accessibility grant.
reset-perms:
	tccutil reset Accessibility $(BUNDLE_ID)

logs:
	log stream --style compact --level info --predicate 'subsystem == "$(BUNDLE_ID)"'

clean:
	rm -rf .build build
