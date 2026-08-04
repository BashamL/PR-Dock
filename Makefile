.PHONY: build test app run install clean

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh

run: app
	open "build/PR Dock.app"

install: app
	rm -rf "$(HOME)/Applications/PR Dock.app"
	mkdir -p "$(HOME)/Applications"
	cp -R "build/PR Dock.app" "$(HOME)/Applications/PR Dock.app"
	open "$(HOME)/Applications/PR Dock.app"

clean:
	swift package clean
	rm -rf build
