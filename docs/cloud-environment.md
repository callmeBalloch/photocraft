# PhotoCraft in Codex cloud

This setup prepares the existing `/workspace/photocraft` checkout on the Debian 13
cloud image. Each cloud task is already isolated; use its checkout and create a
Git worktree only when the user explicitly requests one.

Run the setup script from the checkout:

```sh
bash scripts/cloud-environment-setup.sh
```

It installs Rust 1.95.0, rustfmt, clippy, the WebAssembly target, verified Debian
development libraries, Xvfb, and Mesa under `/workspace/.photocraft-env`. It builds
the desktop app and CLI with HEIF enabled using the existing Cargo lockfile. It
does not require root or edit application code, manifests, or lockfiles. Debian
packages retain signature and checksum verification; Rust downloads retain TLS
and artifact verification.

Activate the environment in each new shell:

```sh
source /workspace/.photocraft-env/activate.sh
cd /workspace/photocraft
```

Activation sets the workspace-local toolchain, library and pkg-config paths,
four build jobs, and profiles without debug symbols to conserve disk space.
The default workflow needs no external credentials or services. Required download
hosts are `sh.rustup.rs`, `static.rust-lang.org`, `index.crates.io`,
`static.crates.io`, `deb.debian.org`, and `security.debian.org`.

## Headless editing

```sh
target/debug/photocraft-cli run --new '{"width":96,"height":64,"background":"white"}' --cmd document.inspect
```

Use `photocraft-cli mcp` or `serve` for persistent headless automation. Supply
explicit `--automation-read-root` and `--automation-write-root` directories for
file access.

## Desktop startup

Processes must restart after an environment is restored. Check for an existing
healthy display and control server before starting another. Launch these commands
in separate persistent terminal sessions after activation:

```sh
Xvfb :99 -screen 0 1280x900x24 -nolisten tcp -ac -extension MIT-SHM > /workspace/.photocraft-env/xvfb.log 2>&1
```

```sh
bash /workspace/.photocraft-env/start-desktop.sh > /workspace/.photocraft-env/desktop.log 2>&1
```

The launcher uses a writable runtime directory and Mesa cache, local preferences,
loopback control port 7878, and a private generated control-token file. When
preferences are absent, it initializes CPU rendering for the cloud machine's
software graphics adapter. Existing preferences are preserved. Automation file
access is limited to `/workspace/.photocraft-env/work`. Never print or commit the
token, or pass its value on the command line. Stop only processes you started.

Verify startup with the generated functional smoke check:

```sh
python3 /workspace/.photocraft-env/desktop-smoke.py
```

It authenticates, creates a throwaway document, adds a layer, saves `.pcraft`,
exports PNG, and captures the rendered window. It checks document content and
PNG dimensions, writing artifacts outside the checkout. It creates a new document;
use it when validating startup. Inspect `desktop.log` and `xvfb.log` on failure.

## Validation

The onboarding checks, run from the checkout after activation, are:

```sh
cargo fmt --all -- --check
cargo test --locked -p photocraft-cli -p photocraft-automation --features photocraft-cli/heif
cargo run --locked -p xtask -- layers
cargo run --locked -p xtask -- wasm
```

These checks passed during onboarding: 93 selected CLI/MCP tests, the desktop
smoke check, formatting, dependency layering, and all WebAssembly checks. The
installation was repeated successfully using cached dependencies. Read
`AGENTS.md` for checks required by subsequent code changes.

Full workspace and external corpus suites, optional craft-fonts, release packaging,
and a served Trunk web build are separate workflows. Hardware GPU acceleration
was not validated. Keep generated files outside the checkout or in ignored paths,
and inspect `git status --short` after setup.

For reusable Codex configuration, use the setup script contents as `install_script`
and register the activation, desktop startup, and readiness instructions above in
`start_skill`. Saving configuration does not start services or publish a snapshot;
review and publish through environment settings.
