#!/bin/bash
# Installation of Razer Viper Ultimate Battery Plasmoid
# openSUSE Tumbleweed

PLASMOID_ID="org.kde.plasma.razerviperul"
INSTALL_DIR="$HOME/.local/share/plasma/plasmoids/$PLASMOID_ID"
ERRORS=0

echo "=== Razer Viper Ultimate Battery Plasmoid ==="
echo "=== openSUSE Tumbleweed                   ==="
echo ""

# ── Dependency check ──────────────────────────────────────────────────

echo "[1/3] Dependency check..."
echo ""

# python3-dbus installed
if python3 -c "import dbus" 2>/dev/null; then
    echo "  ✓ python3 dbus python installed"
else
    echo "  ✗ python3 dbus python not found"
    echo "    Install manual:"
    echo "      sudo zypper install python313-dbus-python"
    echo ""
    ERRORS=$((ERRORS + 1))
fi

# openrazer-daemon installed
if command -v openrazer-daemon &>/dev/null; then
    echo "  ✓ openrazer-daemon installed"
else
    echo "  ✗ openrazer not found"
    echo "    Install manual:"
    echo "      sudo zypper addrepo https://download.opensuse.org/repositories/hardware/openSUSE_Tumbleweed/hardware.repo"
    echo "      sudo zypper refresh"
    echo "      sudo zypper install openrazer-meta"
    echo ""
    ERRORS=$((ERRORS + 1))
fi

# openrazer-daemon running
if systemctl is-active --user openrazer-daemon &>/dev/null; then
    echo "  ✓ openrazer-daemon running"
else
    echo "  ✗ openrazer-daemon not running"
    echo "    Run manual:"
    echo "      systemctl --user enable --now openrazer-daemon"
    echo ""
    ERRORS=$((ERRORS + 1))
fi

# groups plugdev
if groups | grep -q plugdev; then
    echo "  ✓ user found in plugdev"
else
    echo "  ✗ user not found in plugdev"
    echo "    Run manually and re-login or reboot system:"
    echo "      sudo gpasswd -a $USER plugdev"
    echo ""
    ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Checkout — qa ──────────────────────────────

if [ "$ERRORS" -gt 0 ]; then
    echo "  ⚠ Found problems: $ERRORS. The plasmoid may not work without fixing them."
    read -p "  Install the plasmoid anyway? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 1
    fi
fi

# ── Install ────────────────────────────────────────────────────

echo "[2/3] Plasmoid installation..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp -r package/* "$INSTALL_DIR/"
echo "  ✓ Copied to $INSTALL_DIR"
echo ""

# ── Re-launch plasmashell ─────────────────────────────────────────────────

echo "[3/3] Restarting plasmashell..."
kquitapp6 plasmashell 2>/dev/null || kquitapp5 plasmashell 2>/dev/null || true
sleep 2
plasmashell --replace &>/dev/null &
disown
echo "  ✓ plasmashell restarted"
echo ""

echo "=== Done! ==="
echo ""
echo "Add the widget to the panel:"
echo "  → RMB on the panel → Add widgets"
echo "  → Find 'Razer Viper Ultimate Battery'"
echo ""
echo "Or test without restart:"
echo "  plasmawindowed $PLASMOID_ID"
