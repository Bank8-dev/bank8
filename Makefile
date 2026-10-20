# SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
# SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
# SPDX-FileCopyrightText: Copyright Contributors to the Bank8
# SPDX-License-Identifier: Apache-2.0

# Makefile — bank8/ vertical group (RS §4.4)
#
# Group build in DAG order: the bank8-sdk facade first, then the services.
# NO docker-compose here — the platform group (../sentin8/) owns the dev
# infra (PostgreSQL 18 + Valkey, §2.2.1); this vertical's services consume
# it over localhost. Each child repo is independent; its own `cargo build`
# is self-sufficient — this file is convenience.

SHELL := /bin/bash
CARGO ?= cargo

# Build identity stamps (BUILDID-1, sentin8-build-info README §3): the
# stamps ride the SAME shell line as the cargo command — make runs each
# recipe line in its own shell, so a standalone `export …` line would
# evaporate before cargo starts. The hash resolves via PLAIN `git
# rev-parse` (no -C path): the stamp expands AFTER the `cd` into the
# repo, so a repo-relative `git -C` would resolve from INSIDE and miss
# (stamping every binary EMPTY). Inside the build-services loop the
# `cd bank8-$$s` has already happened when the prefix expands.
stamp_env = SENTIN8_BUILD_PROFILE=$(if $(RELEASE),release,debug) SENTIN8_GIT_SHA=$$(git rev-parse --short HEAD 2>/dev/null)

SERVICES := ledger payments fdx reporting risk compliance
APPS := admin eteller efintech ebank

.PHONY: help build build-sdk build-services test status enroll start stop

help: ## Show this help
	@echo "bank8/ vertical group"
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

build: build-sdk build-services ## Build the group in DAG order

build-sdk: ## Build the bank8 facade workspace (services depend on this)
	@cd bank8-sdk && $(call stamp_env,bank8-sdk) $(CARGO) build

build-services: build-sdk ## Build every bank8 service repo
	@for s in $(SERVICES); do \
		echo "=== bank8-$$s ==="; \
		(cd bank8-$$s && $(call stamp_env,bank8-$$s) $(CARGO) build) || exit 1; \
	done

test: ## Run the SDK facade tests + per-service suites
	@cd bank8-sdk && $(call stamp_env,bank8-sdk) $(CARGO) test
	@for s in $(SERVICES); do (cd bank8-$$s && $(call stamp_env,bank8-$$s) $(CARGO) test) || true; done

test-openapi: ## Run every bank8 drift-guard test (OAPEC §4.8 — router↔spec sweep)
	@for d in bank8-*/; do \
		[ -f "$$d/tests/openapi_drift.rs" ] || continue; \
		echo "==> drift-guard: $$d"; \
		(cd $$d && $(call stamp_env,$(basename $$d)) $(CARGO) test --test openapi_drift) || exit 1; \
	done

# The prefix export rides the SAME shell line as the CLI command (see
# stamp_env — make runs each recipe line in its own shell). It must be
# explicit here: composable enroll (RS §6) merges this group's repo
# fragments into a temp aggregate in /tmp, so the CLI's own vertical-root
# fallback (target/release under the registry's parent dir) can never see
# this group's dev builds — binary resolution depends entirely on
# SENTIN8_CAPTAIN_BINARY_PREFIX. This export also overrides any ambient
# mis-set variable (a bare repo ROOT dir contains no binary files).
enroll: ## Enroll every bank8 repo (composable registration, RS §6)
	@export SENTIN8_CAPTAIN_BINARY_PREFIX="$(PREFIX)"; \
	cd ../sentin8/sentin8-cli && $(call stamp_env,sentin8-cli) $(CARGO) run --bin sentin8-cli -- vertical enroll \
		$(patsubst %,../../bank8/bank8-%,$(SERVICES)) \
		$(patsubst %,../../bank8/bank8-%,$(APPS))

status: ## Per-repo HEADs
	@for d in */; do \
		[ -d "$$d/.git" ] || continue; \
		printf "%-22s %s\n" "$$d" "$$(git -C $$d log --oneline -1 2>/dev/null | head -c 60)"; \
	done

# ── Fleet run (STARTSCOPE-1, RS §4.5.2 — the three-level rule) ──────────
# This group's fleet scope: `make start` boots ONLY the platform base +
# THIS vertical — the SENTIN8_SERVICES boot pin when captain is down,
# the idempotent `captain start <types>` API form when it is up. The
# platform base is the minimal plane a vertical's services call at boot
# (acme cert mints, auth identity, proxy ingress, bus events, sys
# registration, bff tokens, web apps); everything else fails open
# (RS §5.1). The catalog stays the FULL union — other groups join the
# running fleet via their own group start; `make stop` here stops only
# this group's instances (the captain and the platform stay up).
SERVICE_TYPES := $(patsubst %,bank8:%,$(SERVICES))
PLATFORM_BASE := sentin8:acme,sentin8:auth,sentin8:proxy,sentin8:bus,sentin8:sys,sentin8:bff,sentin8:web
GROUP_SCOPE := $(PLATFORM_BASE),$(SERVICE_TYPES)

# Tree anchors (RS §4.5.1 discipline): the sibling sentin8-cli, the root
# .env, ONE absolute tree run dir, and the binary-prefix chain covering
# this group's + the platform's built target dirs. Entries are ABSOLUTE —
# `vertical enroll` runs the CLI from ../sentin8/sentin8-cli, where a
# relative `bank8-*/target/debug` entry would resolve against the CLI's
# own cwd and miss.
TREE_ROOT := $(abspath ..)
PLATFORM := $(TREE_ROOT)/sentin8
CLI_DIR := $(PLATFORM)/sentin8-cli
ROOT_ENV := $(TREE_ROOT)/.env
BINARY_DIR = $(if $(RELEASE),release,debug)
CLI_BIN := $(firstword $(wildcard $(CLI_DIR)/target/$(BINARY_DIR)/sentin8-cli))
CLI_RUN = $(if $(CLI_BIN),$(CLI_BIN),cargo run --quiet --manifest-path $(CLI_DIR)/Cargo.toml --bin sentin8-cli --)
SPACE := $(empty) $(empty)
PREFIX_DIRS := $(wildcard $(PLATFORM)/sentin8-*/target/$(BINARY_DIR)) $(abspath $(wildcard */target/$(BINARY_DIR)))
PREFIX := $(subst $(SPACE),:,$(strip $(PREFIX_DIRS:%=%)))

define group_rundir
export SENTIN8_RUN_DIR="$(TREE_ROOT)/.run"; \
export SENTIN8_LOG_DIR="$(TREE_ROOT)/.run/logs"; \
export SENTIN8_CAPTAIN_SOCK="$(TREE_ROOT)/.run/captain.sock"
endef

start: ## Start THIS group: platform base + bank8 (STARTSCOPE-1; captain boots scoped or joins live)
	@test -f $(ROOT_ENV) || { echo "ERROR: no $(ROOT_ENV) — copy .env.example" >&2; exit 1; }
	@export SENTIN8_CAPTAIN_BINARY_PREFIX="$(PREFIX)"; \
	export SENTIN8_PG_POOL_MAX=$${SENTIN8_PG_POOL_MAX:-8}; \
	set -a; . $(ROOT_ENV); set +a; \
	$(group_rundir); \
	if [ -z "$$(docker compose -f $(PLATFORM)/docker-compose.yml ps --status=running -q 2>/dev/null)" ]; then \
		echo "→ dev infra down — starting PG 18 + Valkey (RS §2.2.1)"; \
		docker compose -f $(PLATFORM)/docker-compose.yml up -d >/dev/null || exit 1; \
		for i in $$(seq 1 30); do \
			n=$$(docker compose -f $(PLATFORM)/docker-compose.yml ps --status=running -q 2>/dev/null | wc -l); \
			[ "$$n" -ge 2 ] && break; sleep 1; \
		done; \
	fi; \
	if $(CLI_RUN) captain services --no-infra >/dev/null 2>&1; then \
		echo "→ captain up — starting bank8 via API (idempotent): $(SERVICE_TYPES)"; \
		$(CLI_RUN) captain start $(SERVICE_TYPES); \
	else \
		echo "→ captain down — scoped boot (platform base + bank8, STARTSCOPE-1)"; \
		export SENTIN8_SERVICES="$(GROUP_SCOPE)"; \
		$(CLI_RUN) captain start; \
	fi

stop: ## Stop ONLY this group's instances; captain + platform stay up
	@set -a; . $(ROOT_ENV); set +a; \
	$(group_rundir); \
	if ! $(CLI_RUN) captain services --no-infra >/dev/null 2>&1; then \
		echo "(captain not running — nothing to stop)"; exit 0; \
	fi; \
	keys="$$($(CLI_RUN) captain services --no-infra 2>/dev/null | awk -v types="$(SERVICE_TYPES)" 'BEGIN{split(types,t," "); for(i in t) want[t[i]]=1} want[$$1]{print $$(NF-1)}')"; \
	if [ -z "$$keys" ]; then echo "(no bank8 instances running)"; exit 0; fi; \
	for k in $$keys; do \
		echo "→ stopping $$k"; \
		$(CLI_RUN) captain stop-instance "$$k" || exit 1; \
	done


