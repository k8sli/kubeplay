# It's necessary to set this because some environments don't link sh -> bash.
export SHELL := /bin/bash

# It's necessary to set the errexit flags for the bash shell.
export SHELLOPTS := errexit

# Current version of the project.
VERSION                    ?= $(shell git describe --tags --always --dirty)
BRANCH                     ?= $(shell git branch | grep \* | cut -d ' ' -f2)
GITCOMMIT                  ?= $(shell git rev-parse HEAD)
GITTREESTATE               ?= $(if $(shell git status --porcelain),dirty,clean)
RELEASE_TIME               ?= $(shell date +'%Y-%m-%d')

# All targets.
.PHONY: merge-dockerfile
merge-dockerfile:
	@find build/os-packages -type f -name 'Dockerfile.os.*' \
	| sort | xargs -L1 grep -Ev 'FROM scratch|COPY --from=os-' > build/os-packages/Dockerfile.all
	@echo 'FROM scratch' >> build/os-packages/Dockerfile.all
	@find build/os-packages -type f -name 'Dockerfile.os.*' \
	| sort | xargs -L1 grep 'COPY --from=os-' >> build/os-packages/Dockerfile.all
