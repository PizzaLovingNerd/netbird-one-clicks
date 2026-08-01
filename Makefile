SHELL := /bin/bash

.PHONY: sync validate syntax generated ansible packer release

sync:
	./scripts/sync-marketplace-assets.sh

syntax:
	./scripts/validate.sh syntax

generated:
	./scripts/validate.sh generated

ansible:
	./scripts/validate.sh ansible

packer:
	./scripts/validate.sh packer

release:
	./scripts/validate.sh release

validate:
	./scripts/validate.sh all
