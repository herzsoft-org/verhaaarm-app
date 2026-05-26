.PHONY: deps analyze test build-web build-apk test-build

deps:
	flutter pub get

analyze:
	flutter analyze

test:
	flutter test

build-web:
	flutter build web

build-apk:
	flutter build apk --debug

test-build: analyze test build-web
