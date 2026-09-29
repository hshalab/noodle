#!/bin/bash
# Runs inside an arm64 ubuntu:22.04 container (GCC 11.4, as the Kata build).
# /computer is the Computer directory; /kbuild is scratch space for sources and output.
# The shipped Kata kernel's embedded config is the base, plus display.fragment.
set -euo pipefail
version=6.18.35
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq build-essential bc bison flex libelf-dev libssl-dev xz-utils curl python3 >/dev/null
cd /kbuild
[ -f "linux-$version.tar.xz" ] || curl -fsSLO "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$version.tar.xz"
mkdir /src && tar -xf "linux-$version.tar.xz" -C /src --strip-components=1
cd /src
python3 - /computer/Resources/Runtime/vmlinux-arm64 > .config <<'PY'
import gzip, sys
data = open(sys.argv[1], 'rb').read()
start = data.index(b'IKCFG_ST') + 8
sys.stdout.write(gzip.decompress(data[start:data.index(b'IKCFG_ED', start)]).decode())
PY
scripts/kconfig/merge_config.sh -m .config /computer/Kernel/display.fragment
make olddefconfig
for option in DRM_VIRTIO_GPU FRAMEBUFFER_CONSOLE USB_XHCI_HCD USB_HID HID_GENERIC INPUT_EVDEV VIRTIO_INPUT; do
    grep -q "^CONFIG_$option=y" .config || { echo "missing CONFIG_$option" >&2; exit 1; }
done
make -j"$(nproc)" Image
cp arch/arm64/boot/Image /kbuild/vmlinux-arm64-display
echo BUILD_OK
