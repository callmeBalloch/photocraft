#!/usr/bin/env bash
set -euo pipefail
photocraft_env=/workspace/.photocraft-env
mkdir -p "$photocraft_env" "$photocraft_env/apt/lists/partial" "$photocraft_env/apt/archives/partial" "$photocraft_env/apt/empty" "$photocraft_env/apt/log" "$photocraft_env/sysroot"
export CARGO_HOME="$photocraft_env/cargo"
export RUSTUP_HOME="$photocraft_env/rustup"
export PATH="$CARGO_HOME/bin:$PATH"
if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o "$photocraft_env/rustup-init.sh"
  sh "$photocraft_env/rustup-init.sh" -y --no-modify-path --profile minimal --default-toolchain 1.95.0 --component rustfmt --component clippy --target wasm32-unknown-unknown
fi
rustup toolchain install 1.95.0 --profile minimal --component rustfmt --component clippy --target wasm32-unknown-unknown
rustup default 1.95.0
cat > "$photocraft_env/apt/sources.list" <<'PHOTOCRAFT_SOURCES'
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://deb.debian.org/debian trixie main
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://deb.debian.org/debian trixie-updates main
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://security.debian.org/debian-security trixie-security main
PHOTOCRAFT_SOURCES
cat > "$photocraft_env/apt/apt.conf" <<'PHOTOCRAFT_APT'
Dir::Etc::sourcelist "/workspace/.photocraft-env/apt/sources.list";
Dir::Etc::sourceparts "/workspace/.photocraft-env/apt/empty";
Dir::Etc::parts "/workspace/.photocraft-env/apt/empty";
Dir::State::lists "/workspace/.photocraft-env/apt/lists";
Dir::Cache::archives "/workspace/.photocraft-env/apt/archives";
Dir::Cache::pkgcache "/workspace/.photocraft-env/apt/pkgcache.bin";
Dir::Cache::srcpkgcache "/workspace/.photocraft-env/apt/srcpkgcache.bin";
Dir::Log "/workspace/.photocraft-env/apt/log";
Debug::NoLocking "true";
APT::Sandbox::User "agent";
APT::Update::Error-Mode "any";
PHOTOCRAFT_APT
APT_CONFIG="$photocraft_env/apt/apt.conf" apt-get update
APT_CONFIG="$photocraft_env/apt/apt.conf" apt-get --download-only --no-install-recommends -y install libxkbcommon-dev libwayland-dev libx11-dev libxrandr-dev libxi-dev libgl1-mesa-dev libgtk-3-dev xvfb xauth mesa-vulkan-drivers
for photocraft_deb in "$photocraft_env"/apt/archives/*.deb; do
  dpkg-deb -x "$photocraft_deb" "$photocraft_env/sysroot"
done
cat > "$photocraft_env/activate.sh" <<'PHOTOCRAFT_ACTIVATE'
export CARGO_HOME=/workspace/.photocraft-env/cargo
export RUSTUP_HOME=/workspace/.photocraft-env/rustup
export PATH=/workspace/.photocraft-env/cargo/bin:/workspace/.photocraft-env/sysroot/usr/bin:$PATH
export CARGO_BUILD_JOBS=4
export CARGO_PROFILE_DEV_DEBUG=0
export CARGO_PROFILE_TEST_DEBUG=0
export PKG_CONFIG_PATH=/workspace/.photocraft-env/sysroot/usr/lib/x86_64-linux-gnu/pkgconfig:/workspace/.photocraft-env/sysroot/usr/share/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=/workspace/.photocraft-env/sysroot
export LIBRARY_PATH=/workspace/.photocraft-env/sysroot/usr/lib/x86_64-linux-gnu
export LD_LIBRARY_PATH=/workspace/.photocraft-env/sysroot/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
PHOTOCRAFT_ACTIVATE
cat > "$photocraft_env/start-desktop.sh" <<'PHOTOCRAFT_DESKTOP'
#!/usr/bin/env bash
set -euo pipefail
source /workspace/.photocraft-env/activate.sh
cd /workspace/photocraft
mkdir -p /workspace/.photocraft-env/private /workspace/.photocraft-env/work /workspace/.photocraft-env/runtime /workspace/.photocraft-env/config /workspace/.photocraft-env/cache
chmod 700 /workspace/.photocraft-env/private /workspace/.photocraft-env/runtime
if [ ! -e /workspace/.photocraft-env/config/preferences.json ]; then
  printf '%s\n' '{"performance":{"renderingMode":"cpu","useGpu":false}}' > /workspace/.photocraft-env/config/preferences.json
fi
export DISPLAY=:99
export XDG_RUNTIME_DIR=/workspace/.photocraft-env/runtime
export XDG_CACHE_HOME=/workspace/.photocraft-env/cache
export PHOTOCRAFT_CONFIG_DIR=/workspace/.photocraft-env/config
export VK_DRIVER_FILES=/workspace/.photocraft-env/sysroot/usr/share/vulkan/icd.d/lvp_icd.json
export WGPU_BACKEND=vulkan
exec target/debug/photocraft --control 7878 --control-token-file /workspace/.photocraft-env/private/control.token --automation-read-root /workspace/.photocraft-env/work --automation-write-root /workspace/.photocraft-env/work
PHOTOCRAFT_DESKTOP
cat > "$photocraft_env/desktop-smoke.py" <<'PHOTOCRAFT_SMOKE'
import json
import socket
import struct
import time
from pathlib import Path

root = Path('/workspace/.photocraft-env')
deadline = time.monotonic() + 45
while True:
    try:
        token = (root / 'private/control.token').read_text().strip()
        conn = socket.create_connection(('127.0.0.1', 7878), timeout=5)
        break
    except (OSError, FileNotFoundError):
        if time.monotonic() >= deadline:
            raise RuntimeError('Desktop control server did not become ready; inspect desktop.log')
        time.sleep(0.5)
conn.settimeout(30)
stream = conn.makefile('rwb')

def call(method, params=None):
    req = {'id': method, 'method': method, 'params': params or {}}
    stream.write((json.dumps(req) + '\n').encode())
    stream.flush()
    reply = json.loads(stream.readline())
    assert reply.get('ok') is True, f'{method} failed'
    return reply.get('result')

call('auth', {'token': token})
state = call('ui.inspect')
(root / 'desktop-state.json').write_text(json.dumps(state, indent=2))
call('engine.execute', {'command': 'file.new', 'params': {'width': 96, 'height': 64, 'background': 'white'}})
call('engine.execute', {'command': 'layer.new.layer', 'params': {'name': 'Onboarding'}})
doc = call('engine.execute', {'command': 'document.inspect'})
(root / 'desktop-document.json').write_text(json.dumps(doc, indent=2))
assert doc['width'] == 96 and doc['height'] == 64
assert any(layer['name'] == 'Onboarding' for layer in doc['layers'])
call('app.save', {'path': 'desktop-smoke.pcraft'})
call('app.save', {'path': 'desktop-smoke.png'})
call('ui.screenshot', {'path': 'desktop-screenshot.png'})
for name in ['desktop-smoke.png', 'desktop-screenshot.png']:
    data = (root / 'work' / name).read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    size = struct.unpack('>II', data[16:24])
    if name == 'desktop-smoke.png':
        assert size == (96, 64)
    else:
        assert size[0] >= 500 and size[1] >= 300
assert (root / 'work/desktop-smoke.pcraft').stat().st_size > 100
print('Desktop smoke passed: authenticated control, document creation, layer editing, native save, PNG export, and window screenshot.')
stream.close()
conn.close()
PHOTOCRAFT_SMOKE
source "$photocraft_env/activate.sh"
pkg-config --modversion xkbcommon wayland-client x11 xrandr xi gl gtk+-3.0
cd /workspace/photocraft
cargo fetch --locked
cargo build --locked -p photocraft -p photocraft-cli --features heif
target/debug/photocraft-cli --version
git status --short
