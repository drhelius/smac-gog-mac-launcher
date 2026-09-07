.PHONY: all app test clean dist sign notarize

all: app

app:
	python3 scripts/build.py

test:
	swift test
	python3 -m unittest discover -s Tests/Packaging -p 'test_*.py'
	bash -n scripts/notarize-ci.sh

dist: app
	python3 scripts/release.py package

sign:
	python3 scripts/release.py sign

notarize:
	python3 scripts/release.py notarize

clean:
	rm -rf .build build dist
