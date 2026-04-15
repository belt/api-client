# syntax=docker/dockerfile:1

# Multi-stage: base → production | development
# Ruby 3.x/4.x via RUBY_VERSION. Gem manager: Ore Light.
ARG RUBY_VERSION=3.4.8

# Native extension build toolchain — shared by gems-base and development.
# Defined globally so both stages reference the same list (keep in sync).
ARG BUILD_PACKAGES="build-essential cmake pkg-config \
    libcurl4-openssl-dev libffi-dev libgit2-dev libyaml-dev git"

# Digest-pin for CI reproducibility. Obtain via:
#   docker manifest inspect ruby:3.4.8-slim \
#     | jq -r '.config.digest'
# Leave empty for local dev (falls back to tag-only).
# CI/versioned builds should set RUBY_DIGEST to ensure immutable base
# image resolution — the production stage does not enforce this at build
# time, so pinning is the caller's responsibility.
ARG RUBY_DIGEST=""

# JIT: RUBY_YJIT_ENABLE=1 or RUBY_ZJIT_ENABLE=1 (mutually exclusive)
ARG RUBY_YJIT_ENABLE=1
ARG RUBY_ZJIT_ENABLE=""

# mikefarah/yq (Go static binary) — pinned version + per-arch SHA-256.
# SHA-256 checksums pinned per-arch for reproducible builds.
# Override via --build-arg for version bumps
ARG YQ_VERSION="4.47.2"
ARG YQ_SHA256_AMD64="1bb99e1019e23de33c7e6afc23e93dad72aad6cf2cb03c797f068ea79814ddb0"
ARG YQ_SHA256_ARM64="05df1f6aed334f223bb3e6a967db259f7185e33650c3b6447625e16fea0ed31f"

# Ore Light installer args — override via --build-arg.
# Production builds MUST set ORE_SHA256 explicitly
ARG ORE_SHA256="7a442ae9ccf36f8612993e6e2ed0cf5d8c974145d7de2d97aba9f985cee908ab"
ARG ORE_COMMIT="811cee6f49f4946cddf5e950149fe91bcae8acbb"

# apt retry configuration — override via --build-arg APT_RETRIES.
# Balances resilience vs fast failure. Set to 0 for immediate failure,
# 3-5 for flaky networks. Default: 2 for production, 1 for development
ARG APT_RETRIES=2

# Cache busting ARGs for BuildKit mounts
#
# Use these bumps to clear corrupted caches, force fetching newer upstream versions,
# or clear stale artifacts tracking missing local dependencies.
#
# Supplying a value (e.g., a timestamp via --build-arg) forces Docker to invalidate
# the layer cache for the step that consumes the ARG. Inside that step, the value
# is used to explicitly clear the contents of the respective --mount=type=cache.
# - CACHE_BUMP_APT: Clears /var/cache/apt and /var/lib/apt/lists before apt-get update
# - CACHE_BUMP_GEMS: Clears /app/vendor/bundle/cache before ore / gem install
ARG CACHE_BUMP_APT=""
ARG CACHE_BUMP_GEMS=""

# --- HARDENED-BASE: shared curl for download stages (ca-certificates inherited) ---
FROM ruby:${RUBY_VERSION}-slim${RUBY_DIGEST:+@${RUBY_DIGEST}} AS hardened-base
ARG APT_RETRIES

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
RUN printf 'path-exclude=/usr/share/man/*\n\
path-exclude=/usr/share/doc/*\n\
path-exclude=/usr/share/info/*\n\
path-exclude=/usr/share/lintian/*\n\
path-exclude=/usr/share/linda/*\n' \
        > /etc/dpkg/dpkg.cfg.d/01-nodoc \
    && echo 'force-unsafe-io' > /etc/dpkg/dpkg.cfg.d/02-unsafe-io \
    && echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/01-no-translations \
    && echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/02-no-recommends \
    && echo 'Acquire::GzipIndexes "true";' > /etc/apt/apt.conf.d/03-gzip-indexes \
    && echo "Acquire::Retries \"${APT_RETRIES}\";" > /etc/apt/apt.conf.d/04-retries \
    && apt-get update -qq \
    && apt-get install -y curl \
    && rm -rf /var/cache/apt/* /var/lib/apt/lists/*

# --- ORE-FETCH: download + verify Ore Light installer ---
# Checksum verification (fail-fast):
#   1. Reject branch URIs missing ORE_SHA256 — before any download.
#   2. Download the script.
#   3. If ORE_SHA256 is set, verify against it directly.
#   4. If ORE_SHA256 is blank (commit-SHA URI), fetch upstream checksums.txt
#      and verify against that.
#   Production builds MUST set ORE_SHA256 explicitly.
FROM hardened-base AS ore-fetch
ARG ORE_COMMIT
ARG ORE_SHA256
ARG REPO_BASE_URI="https://raw.githubusercontent.com/contriboss/ore-light"
ARG ORE_CHECKSUMS_URI="${REPO_BASE_URI}/${ORE_COMMIT}/scripts/checksums.txt"
ARG ORE_URI="${REPO_BASE_URI}/${ORE_COMMIT}/scripts/install.sh"

RUN ore_err() { \
      printf '{"level":"error","stage":"ore-fetch"' >&2; \
      printf ',"check":"%s","message":"%s"' "$1" "$2" >&2; \
      printf '%s}\n' "${3:+,$3}" >&2; exit 1; \
    } \
    && ore_log() { \
      printf '{"level":"info","stage":"ore-fetch"' >&2; \
      printf ',"check":"%s","message":"%s"}\n' "$1" "$2" >&2; \
    } \
    && if [ -z "${ORE_SHA256}" ] \
       && ! echo "${ORE_URI}" \
            | grep -qE '/[0-9a-f]{40}/'; then \
        ore_err "ore_sha256_guard" \
          "ORE_URI points to a branch" \
          "\"ore_uri\":\"${ORE_URI}\""; \
       fi \
    && curl -fsSL -o /tmp/ore-install.sh "${ORE_URI}" \
    && if [ -n "${ORE_SHA256}" ]; then \
        echo "${ORE_SHA256}  /tmp/ore-install.sh" \
          | sha256sum -c - \
        || ore_err "ore_sha256" \
             "checksum mismatch" \
             "\"expected\":\"${ORE_SHA256}\""; \
       else \
        ore_log "ore_checksums_txt" \
          "ORE_SHA256 blank — fetching checksums.txt"; \
        curl -fsSL -o /tmp/checksums.txt \
          "${ORE_CHECKSUMS_URI}" \
        || ore_err "ore_checksums_txt" \
             "failed to fetch checksums.txt" \
             "\"uri\":\"${ORE_CHECKSUMS_URI}\""; \
        cd /tmp \
        && sha256sum -c checksums.txt --ignore-missing \
        || ore_err "ore_checksums_txt" \
             "checksums.txt verification failed" \
             "\"uri\":\"${ORE_CHECKSUMS_URI}\""; \
       fi

# --- YQ-FETCH: download + verify mikefarah/yq static binary ---
# mikefarah/yq (Go static binary) — Debian apt "yq" is kislyuk/yq,
# a Python jq wrapper that drops YAML comments and lacks TOML/XML/CSV.
#
# Checksum verification (fail-fast):
#   1. Resolve the SHA-256 checksum for the current architecture.
#   2. If the checksum is blank, yq is optional — skip download, succeed.
#   3. Download the static binary.
#   4. Verify against the provided checksum.
# Output directory /tmp/yq-artifacts/ always exists; it contains the binary
# only when a checksum was provided and verification passed.
FROM hardened-base AS yq-fetch
ARG YQ_VERSION
ARG YQ_SHA256_AMD64
ARG YQ_SHA256_ARM64

RUN yq_err() { \
      printf '{"level":"error","stage":"yq-fetch"' >&2; \
      printf ',"check":"%s","message":"%s"' "$1" "$2" >&2; \
      printf '%s}\n' "${3:+,$3}" >&2; exit 1; \
    } \
    && yq_log() { \
      printf '{"level":"info","stage":"yq-fetch"' >&2; \
      printf ',"check":"%s","message":"%s"}\n' "$1" "$2" >&2; \
    } \
    && mkdir -p /tmp/yq-artifacts \
    && arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
         amd64) yq_sha256="${YQ_SHA256_AMD64}" ;; \
         arm64) yq_sha256="${YQ_SHA256_ARM64}" ;; \
         *)     yq_err "yq_arch" \
                  "unsupported architecture" \
                  "\"arch\":\"${arch}\"" ;; \
       esac \
    && if [ -z "${yq_sha256}" ]; then \
        yq_log "yq_skip" \
          "no checksum for ${arch} — skipping yq (optional)"; \
        exit 0; \
       fi \
    && yq_log "yq_download" \
         "fetching yq v${YQ_VERSION} for ${arch}" \
    && curl -fsSL -o /tmp/yq-artifacts/yq \
         "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${arch}" \
    || yq_err "yq_download" \
         "failed to download yq" \
         "\"version\":\"${YQ_VERSION}\",\"arch\":\"${arch}\"" \
    && echo "${yq_sha256}  /tmp/yq-artifacts/yq" \
         | sha256sum -c - \
    || yq_err "yq_sha256" \
         "checksum mismatch" \
         "\"expected\":\"${yq_sha256}\",\"arch\":\"${arch}\"" \
    && chmod +x /tmp/yq-artifacts/yq

# --- BASE: shared foundation ---
FROM hardened-base AS base
ARG APP_UID=10001
ARG APP_GID=10001
ARG RUBYGEMS_VERSION=""
ARG RUBY_YJIT_ENABLE
ARG RUBY_ZJIT_ENABLE
ARG CACHE_BUMP_APT

# Ore installer pre-verified in ore-fetch stage
COPY --from=ore-fetch /tmp/ore-install.sh /tmp/ore-install.sh

# Cache mounts: /var/cache/apt (downloaded .debs) and /var/lib/apt/lists
# (package index) persist across builds via BuildKit. sharing=locked
# serializes access for dpkg's internal locking. No cleanup needed —
# mount contents don't persist into the image layer.
#
# - 01-nodoc: skip manpages/docs for all apt installs in base + descendants.
#             development stage removes this filter if INSTALL_MANPAGES is set
# - libgit2 resolved dynamically (soversion varies by release)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    if [ -n "${CACHE_BUMP_APT}" ]; then rm -rf /var/cache/apt/* /var/lib/apt/lists/* || true; fi \
    && apt-get update -qq \
    && LIBGIT2_RT=$(apt-cache search --names-only '^libgit2-[0-9]' \
        | awk '{print $1}' | sort -V | tail -1) \
    && apt-get install -y \
        tini curl libcurl4 libffi8 libjemalloc2 ${LIBGIT2_RT} \
    && bash /tmp/ore-install.sh --system \
    && rm -rf /tmp/*

# jemalloc tuning: background_thread enables async purging.
# dirty/muzzy decay control how fast freed pages return to the OS.
# 1000ms suits long-running processes; lower (e.g. 500ms) returns
# memory faster for short-lived workloads at slight CPU cost
ENV MALLOC_CONF="background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:1000"
ENV LD_PRELOAD=libjemalloc.so.2

# Fix Bundler 2.6.x require_paths bug (affects faraday 2.14+).
# Pin RubyGems version for reproducible builds, override via --build-arg.
# No-op when already at target version.
# Ruby 4.x ships with RubyGems 4.0.x
RUN target="${RUBYGEMS_VERSION}" \
    && if [ -z "$target" ]; then \
         ruby_major="$(ruby -e 'print RUBY_VERSION.split(".").first')"; \
         if [ "$ruby_major" -ge 4 ]; then target="4.0.6"; \
         else target="3.6.2"; fi; \
       fi \
    && current="$(gem --version)" \
    && if [ "$current" != "$target" ]; then \
         gem update --system "$target" --no-document \
         && (gem uninstall rubygems-update -x 2>/dev/null || true) \
         && rm -rf /usr/local/bundle/cache/*.gem; \
       fi

ENV RUBY_YJIT_ENABLE=${RUBY_YJIT_ENABLE}
ENV RUBY_ZJIT_ENABLE=${RUBY_ZJIT_ENABLE}
ENV BUNDLE_WITHOUT=""

# Override parent image BUNDLE_APP_CONFIG
# (ore misreads the directory as a file)
ENV BUNDLE_APP_CONFIG=/app/.bundle

# Redirect gem install from /usr/local/bundle (root-owned) to
# project-local vendor/bundle.
ENV GEM_HOME=/app/vendor/bundle
ENV BUNDLE_PATH=/app/vendor/bundle
ENV PATH="/app/vendor/bundle/bin:${PATH}"

RUN groupadd -g ${APP_GID} appuser \
    && useradd -u ${APP_UID} -g appuser -m -s /bin/bash appuser

WORKDIR /app

# --- GEMS-BASE: build deps + gem manifest ---
FROM base AS gems-base
ARG BUILD_PACKAGES
ARG RUBY_VERSION
ARG CACHE_BUMP_APT

# apt-get update omitted — shared cache mount populated by base stage.
# BuildKit guarantees base completes first (FROM dependency chain)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get install -y ${BUILD_PACKAGES}

# Sync .tool-versions so Bundler's `ruby file:`
# constraint matches container
COPY --link Gemfile Gemfile.lock api-client.gemspec .tool-versions ./
COPY --link lib/api_client/version.rb lib/api_client/version.rb

RUN echo "ruby ${RUBY_VERSION}" >.tool-versions \
    && install -d -o 10001 -g 10001 /app/vendor/bundle \
    && chown -R 10001:10001 /app

# Disable frozen mode + re-lock for cross-version builds.
# Trade-off: the resulting Gemfile.lock may differ from the repo's
# RUBY VERSION section, so the image lockfile is not bit-for-bit
# reproducible from source. Accepted for multi-version matrix builds.
ENV BUNDLE_DEPLOYMENT=""
ENV BUNDLE_FROZEN=""
USER 10001:10001
RUN bundle lock

# --- GEMS-PRODUCTION: production gems only ---
FROM gems-base AS gems-production
ARG CACHE_BUMP_GEMS

# Cache mount: vendor/bundle/cache holds .gem files for offline re-install.
# sharing=locked serializes concurrent builds. uid/gid match appuser (10001)
ENV BUNDLE_WITHOUT="development:test"
RUN --mount=type=cache,target=/app/vendor/bundle/cache,sharing=locked,uid=10001,gid=10001 \
    if [ -n "${CACHE_BUMP_GEMS}" ]; then rm -rf /app/vendor/bundle/cache/* || true; fi \
    && ore install \
    && find /app/vendor/bundle -name ".git" -type d -prune -exec rm -rf {} + \
    && find /app/vendor/bundle \
        \( -name "*.o" -o -name "*.c" -o -name "*.h" \
        -o -name "*.cpp" -o -name "*.log" \
        -o -name "*.md" -o -name "README*" -o -name "CHANGELOG*" \) \
        -delete \
    || true \
    && find /app/vendor/bundle/ruby/*/gems -maxdepth 2 \
        \( -name spec -o -name test -o -name tests -o -name coverage \) \
        -type d -exec rm -rf {} + || true \
    && find /app/vendor/bundle -name "*.so" -exec strip --strip-unneeded {} + 2> /dev/null || true \
    && rm -rf /app/vendor/bundle/cache/*.gem /app/vendor/bundle/doc/

# --- GEMS-DEVELOPMENT: all gems including dev/test ---
FROM gems-base AS gems-development
ARG CACHE_BUMP_GEMS

# Cache mount: same gem cache as gems-production, shared across builds
RUN --mount=type=cache,target=/app/vendor/bundle/cache,sharing=locked,uid=10001,gid=10001 \
    if [ -n "${CACHE_BUMP_GEMS}" ]; then rm -rf /app/vendor/bundle/cache/* || true; fi \
    && ore install

# --- PRODUCTION: minimal runtime ---
FROM base AS production

COPY --from=gems-production /app/vendor/bundle /app/vendor/bundle

COPY --link --chown=10001:10001 lib/ lib/
COPY --link --chown=10001:10001 config/ config/
COPY --link --chown=10001:10001 bin/docker-healthcheck bin/docker-healthcheck
COPY --link --chown=10001:10001 Gemfile api-client.gemspec Rakefile ./
COPY --from=gems-production /app/Gemfile.lock Gemfile.lock

ARG RUBY_VERSION
RUN echo "ruby ${RUBY_VERSION}" >.tool-versions

ENV BUNDLE_DEPLOYMENT=1
ENV BUNDLE_FROZEN=1
ENV BUNDLE_WITHOUT="development:test"

ARG BUILD_DATE=""
ARG APP_VERSION=""

USER 10001:10001
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "--"]
HEALTHCHECK --interval=60s --timeout=5s --start-period=20s --retries=3 \
    CMD ["/app/bin/docker-healthcheck"]

# No EXPOSE — library gem, not a web server.
# No ports are bound at runtime.

LABEL org.opencontainers.image.title="api-client" \
    org.opencontainers.image.description="api-client production runtime" \
    org.opencontainers.image.variant="production" \
    org.opencontainers.image.source="https://github.com/belt/api-client" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.version="${APP_VERSION}" \
    org.opencontainers.image.ruby.version="${RUBY_VERSION}"

# RUBY_VERSION below is Kernel::RUBY_VERSION
# (exec form, no shell expansion)
CMD ["ore", "exec", "ruby", "-I", "lib", "-e", "require 'api_client'; puts \"ApiClient #{ApiClient::VERSION} ready (Ruby #{RUBY_VERSION})\""]

# --- DEVELOPMENT: full tooling for specs ---
FROM base AS development
ARG BUILD_PACKAGES
ARG RUBY_VERSION
ARG APT_RETRIES=1
ARG BUILD_DATE=""
ARG APP_VERSION=""
ARG CACHE_BUMP_APT

# Feature flags for optional dev tooling (set to "1" to enable).
# INSTALL_MANPAGES: installs manpages + man-db, removes 01-nodoc dpkg filter
# INSTALL_LESS:     installs less, sets PAGER and MANPAGER
# INSTALL_VIM:      installs vim-tiny, sets EDITOR/VISUAL, drops ~/.vimrc for appuser
# INSTALL_MISE:     installs mise (dev tool manager), runs mise install for
#                   shellcheck, shfmt, jq, shellspec from .mise.toml
# yq is installed as a standalone static binary (Go toolchain not needed)
ARG INSTALL_MANPAGES=""
ARG INSTALL_LESS=""
ARG INSTALL_VIM=""
ARG INSTALL_MISE=""

# Override apt retry count for development (1 retry = faster failure feedback).
RUN echo "Acquire::Retries \"${APT_RETRIES}\";" > /etc/apt/apt.conf.d/04-retries

# apt-get update omitted — shared cache mount populated by base stage.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get install -y ${BUILD_PACKAGES} \
    && if [ -n "${INSTALL_MANPAGES}" ]; then \
         rm -f /etc/dpkg/dpkg.cfg.d/01-nodoc \
         && apt-get install -y manpages man-db; \
       fi \
    && if [ -n "${INSTALL_LESS}" ]; then \
         apt-get install -y less; \
       fi \
    && if [ -n "${INSTALL_VIM}" ]; then \
         apt-get install -y vim-tiny; \
       fi \
    && if [ -n "${INSTALL_MISE}" ]; then \
         curl -fsSL https://mise.run \
           | MISE_INSTALL_PATH=/usr/local/bin/mise sh; \
       fi \
    && rm -rf /tmp/* /var/tmp/*

COPY --from=yq-fetch /tmp/yq-artifacts/ /usr/local/bin/
COPY --from=gems-development /app/vendor/bundle /app/vendor/bundle
COPY --link --chown=10001:10001 lib/ lib/
COPY --link --chown=10001:10001 config/ config/
COPY --link --chown=10001:10001 spec/ spec/
COPY --link --chown=10001:10001 doc/ doc/
COPY --link --chown=10001:10001 bin/ bin/
COPY --link --chown=10001:10001 Gemfile Gemfile.lock api-client.gemspec Rakefile ./
COPY --link --chown=10001:10001 .rubocop.yml .rubycritic.yml .standard.yml ./
COPY --link --chown=10001:10001 .mise.toml ./

# Pager / editor env — conditional values baked via ARG→ENV
# (empty ARG ⇒ empty ENV ⇒ no effect at runtime)
# MANPAGER requires both less and manpages to be useful
ENV PAGER="${INSTALL_LESS:+less}"
ENV MANPAGER="${INSTALL_MANPAGES:+${INSTALL_LESS:+less -R}}"
ENV EDITOR="${INSTALL_VIM:+vi}"
ENV VISUAL="${INSTALL_VIM:+vi}"
ENV RSPEC_EXAMPLES_PATH="/app/tmp/examples.txt"

RUN echo "ruby ${RUBY_VERSION}" >.tool-versions
COPY --from=gems-development /app/Gemfile.lock Gemfile.lock

# Minimal vimrc when vim is installed
USER 10001:10001
RUN if [ -n "${INSTALL_VIM}" ]; then \
      mkdir -p /home/appuser \
      && vimrc_lines=( \
           "set nocompatible" \
           "filetype plugin indent on" \
           "syntax on" \
           "set number ruler" \
           "set tabstop=2 shiftwidth=2 expandtab" \
           "set hlsearch incsearch" \
           "set backspace=indent,eol,start" \
         ) \
      && printf '%s\n' "${vimrc_lines[@]}" > /home/appuser/.vimrc; \
    fi

# mise: trust project config + install tools as appuser.
# Runs only when INSTALL_MISE is set. Tools land in
# ~appuser/.local/share/mise/ (persisted in image layer).
#
# yq is stripped from .mise.toml before `mise install` to avoid
# a redundant download — when checksums are provided, the yq-fetch
# stage already supplies a SHA256-verified static binary at
# /usr/local/bin/yq
RUN if [ -n "${INSTALL_MISE}" ]; then \
      mise trust --all \
      && mise install --yes; \
    fi

STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "--"]
HEALTHCHECK --interval=60s --timeout=5s --start-period=30s --retries=3 \
    CMD ["/app/bin/docker-healthcheck"]

LABEL org.opencontainers.image.title="api-client-dev" \
    org.opencontainers.image.description="api-client development + test" \
    org.opencontainers.image.variant="development" \
    org.opencontainers.image.source="https://github.com/belt/api-client" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.version="${APP_VERSION}" \
    org.opencontainers.image.ruby.version="${RUBY_VERSION}"

CMD ["ore", "exec", "rspec", "--format", "progress"]