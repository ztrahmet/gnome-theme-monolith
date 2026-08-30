NAME := Monolith

.PHONY: all fetch build check install uninstall dist preview clean distclean

all: build

fetch:
	@tools/fetch-upstream.sh

build: | vendor
	@tools/build.sh

vendor:
	@tools/fetch-upstream.sh

check: build
	@tools/check.sh

dist: build
	@tools/package.sh

preview: build
	@tools/preview.sh

install: build
	@./install.sh --install

uninstall:
	@./install.sh --uninstall

clean:
	@rm -rf build dist

distclean: clean
	@rm -rf vendor
