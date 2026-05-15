.PHONY: build hotdog-build test run clean shell setup

HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)
HOTDOG_IMAGE ?= hotdog-ticket-assistant:local

export PARANOID_MODE ?= true
RANDOM_ID := $(shell openssl rand -hex 6 2>/dev/null || echo "default")
export SECRET_TARGET_PATH = /run/secrets/gh_$(RANDOM_ID)

setup:
	mkdir -p .pi-data .secrets workspace src
	chmod 700 .pi-data .secrets workspace
	@chmod 600 .secrets/github_token.txt 2>/dev/null || true
	touch .secrets/github_token.txt
	chmod 600 .secrets/github_token.txt
	@if [ -f .env ]; then grep "^GITHUB_TOKEN=" .env | cut -d '=' -f2- > .secrets/github_token.txt; fi
	chmod 400 .secrets/github_token.txt

build: setup
	docker compose build

hotdog-build: setup
	HOTDOG_IMAGE=$(HOTDOG_IMAGE) docker compose build pi-agent

update: setup
	docker compose build --no-cache

test:
	./tests/hotdog-adapter.test.sh

run: setup
	HOST_UID=$(HOST_UID) HOST_GID=$(HOST_GID) docker compose run --rm pi-agent

run-args: setup
	HOST_UID=$(HOST_UID) HOST_GID=$(HOST_GID) docker compose run --rm pi-agent $(args)

shell: setup
	HOST_UID=$(HOST_UID) HOST_GID=$(HOST_GID) docker compose run --entrypoint /bin/bash --rm pi-agent

clean:
	docker compose down