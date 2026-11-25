# Nebius Physical AI Workbench on Intel macOS

This community installer runs the upstream `npa` workflow CLI on Intel macOS.
The tested host was a Mac Pro 5,1 with macOS 14.8.9 and Python 3.12. This project
pins [Nebius Physical AI Workbench at bcdfed482](https://github.com/nebius/nebius-physical-ai/tree/bcdfed48262acb6e18a65d479c5ea8817012c961).

The installer uses Apple Command Line Tools, verified Intel Rust archives, and
a local OpenSSL 3.5.9 build to compile upstream `cryptography==50.0.2`. The
upstream NPA source and its security checks are used as shipped. The Intel
environment excludes `lancedb==0.39.0` and `rerun-sdk==0.38.1`, whose macOS
wheels target ARM64. Local operations that import those packages require a
compatible runtime.

## Install

Prerequisites are Intel macOS, Xcode Command Line Tools, and [uv](https://docs.astral.sh/uv/getting-started/installation/)
with `uv pip install --excludes` support. The install needs internet access for
GitHub, Rust, PyPI, and crates.io.

```sh
git clone https://github.com/lantzmurray/npa-intel-macos.git
cd npa-intel-macos
sh install.sh
```

The script uses directories within this checkout by default. It downloads the
pinned upstream revision to `.npa-upstream`, builds native prerequisites in
`.npa-native`, and installs NPA into `.venv`. The first build can take several
minutes. If you already have a compatible setup, `NPA_SOURCE_DIR`,
`NPA_NATIVE_DIR`, and `NPA_VENV_DIR` accept absolute paths to reuse it.
`NPA_BUILD_JOBS` controls OpenSSL's build parallelism and defaults to six.

## Verify

```sh
.venv/bin/npa workbench workflow --help
sh smoke-test.sh
```

The smoke test validates a workflow, rejects an invalid workflow, expands a
dry-run plan, and verifies that Ed25519 rejects a modified payload. The checks
run locally without cloud job submission. The workflow and cryptography
checks passed on the Intel Mac listed above. A clean install on a second
machine and authenticated cloud operations still need verification.

Upstream NPA is [Apache-2.0 licensed](https://github.com/nebius/nebius-physical-ai/blob/bcdfed48262acb6e18a65d479c5ea8817012c961/LICENSE).
