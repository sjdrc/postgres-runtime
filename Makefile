# postgres-runtime build pipeline. Each target wraps one auditable script
# under scripts/; `make dist` runs the full release pipeline for the host
# platform. All state lives under work/ (gitignored).

SHELL := bash
S := scripts

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
LINK_OS := darwin
else
LINK_OS := linux
endif

.PHONY: all dist fetch verify-source configure build stage third-party prune \
	rewrite-links verify-links manifest package finalize sbom \
	smoke relocation lint clean distclean

all: dist

# Full pipeline: fetch -> verify -> build -> stage -> third-party ->
# prune -> relink -> verify links -> manifest -> package ->
# relocation-test the artifact -> final manifest + SBOM.
dist: fetch verify-source configure build stage third-party prune rewrite-links \
	verify-links manifest package relocation finalize sbom
	@echo "dist complete: work/out/"
	@ls -l work/out/

fetch:
	$(S)/fetch-source.sh

verify-source:
	$(S)/verify-source.sh

configure:
	$(S)/configure.sh

build:
	$(S)/build.sh

stage:
	$(S)/install-stage.sh

third-party:
	$(S)/build-third-party.sh

prune:
	$(S)/prune-stage.sh

rewrite-links:
	$(S)/rewrite-runtime-links-$(LINK_OS).sh

verify-links:
	$(S)/verify-runtime-links-$(LINK_OS).sh

manifest:
	$(S)/generate-manifest.sh prelim

package:
	$(S)/package.sh

relocation:
	$(S)/relocation-test.sh

finalize:
	$(S)/generate-manifest.sh final

sbom:
	$(S)/generate-sbom.sh

# Developer convenience: smoke-test the pruned runtime tree in place
# (the release path exercises the packaged archive via `relocation`).
smoke:
	$(S)/smoke-test.sh --runtime work/runtime/postgres-runtime --workdir work/smoke --phase full

lint:
	shellcheck -x $(S)/*.sh
	$(S)/validate-versions.sh
	$(S)/check-patch-policy.sh
	jq empty runtime-manifest.schema.json
	@echo "lint OK"

clean:
	rm -rf work/build work/stage work/runtime work/out work/smoke work/configure-options.txt

distclean:
	rm -rf work
