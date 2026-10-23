.PHONY: generate check test

generate:
	python3 scripts/bundle-rules.py
	python3 scripts/generate-project.py

check:
	python3 scripts/check-repository.py

test:
	swift test
