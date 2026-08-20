#!/usr/bin/env bash

set -Eeuo pipefail

clear

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
APT_UPDATED=0
APT_ARGS=()

die() { printf '\nError: %s\n' "$1" >&2; exit 1; }
require_root() { [[ "$(id -u)" -eq 0 ]] || die "Run this installer as root. Example: sudo bash DebiLite.sh"; }
is_debian() { [[ -r /etc/os-release ]] || return 1; . /etc/os-release; [[ "${ID:-}" == "debian" || "${ID_LIKE:-}" == *debian* ]]; }
package_installed() { dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null | grep -qx installed; }

apt_update() {
    [[ "$APT_UPDATED" -eq 1 ]] && return 0
    printf '\nUpdating package lists...\n'
    apt-get update
    APT_UPDATED=1
}

install_packages() {
    local missing=() package_name
    for package_name in "$@"; do package_installed "$package_name" || missing+=("$package_name"); done
    [[ "${#missing[@]}" -eq 0 ]] && return 0
    apt_update
    printf '\nInstalling: %s\n' "${missing[*]}"
    apt-get install "${APT_ARGS[@]}" --no-install-recommends "${missing[@]}"
}

ask_yes_no() {
    local question="$1" default_answer="${2:-n}" answer
    if [[ "$default_answer" == "y" ]]; then read -r -p "$question [Y/n]: " answer; [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; else read -r -p "$question [y/N]: " answer; [[ "$answer" =~ ^[Yy]$ ]]; fi
}

choose_multiple() {
    local title="$1"; shift
    local options=("$@") answer item index
    printf '\n%s\n' "$title"
    for index in "${!options[@]}"; do printf '%s) %s\n' "$((index + 1))" "${options[$index]}"; done
    printf 'Separate multiple choices with commas or spaces. Empty answer: none.\n'
    read -r -p "Choose: " answer
    answer="${answer//,/ }"
    CHOICES=()
    for item in $answer; do
        [[ "$item" =~ ^[0-9]+$ && "$item" -ge 1 && "$item" -le "${#options[@]}" ]] && CHOICES+=("${options[$((item - 1))]}")
    done
}

ensure_terminal() {
    local terminal
    for terminal in xterm xfce4-terminal lxterminal sakura alacritty foot konsole gnome-terminal; do command -v "$terminal" >/dev/null 2>&1 && return 0; done
    install_packages xterm
}

install_lightdm() {
    if command -v debconf-set-selections >/dev/null 2>&1; then
        printf '%s\n' 'lightdm shared/default-x-display-manager select /usr/sbin/lightdm' |
            debconf-set-selections
    fi

    install_packages lightdm lightdm-gtk-greeter

    mkdir -p /etc/lightdm/lightdm.conf.d

    cat > /etc/lightdm/lightdm.conf.d/50-debilite.conf <<'EOF'
[Seat:*]
user-session=openbox
EOF

    if command -v systemctl >/dev/null 2>&1; then
        systemctl unmask lightdm.service >/dev/null 2>&1 || true
        systemctl enable lightdm.service >/dev/null 2>&1 || true
        systemctl set-default graphical.target >/dev/null 2>&1 || true
    fi
}

install_core() {
    install_packages sudo nano curl ca-certificates wget gnupg debconf bash coreutils util-linux procps iproute2 iputils-ping grep sed gawk findutils less file openbox xorg xinit dbus-x11 mousepad tint2 obconf
    ensure_terminal
}

configure_openbox() {
    local target_user="${SUDO_USER:-}"
    local target_home

    if [[ -z "$target_user" || "$target_user" == root ]]; then
        target_user="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "nobody" {print $1; exit}')"
    fi

    [[ -n "$target_user" ]] || die "No normal user account was found."

    target_home="$(getent passwd "$target_user" | cut -d: -f6)"

    [[ -n "$target_home" && -d "$target_home" ]] ||
        die "Could not determine the user's home directory."

    mkdir -p "$target_home/.config/openbox"

    cat > "$target_home/.xinitrc" <<'EOF'
#!/bin/sh

exec dbus-run-session -- openbox-session
EOF

    chmod 755 "$target_home/.xinitrc"

    cat > "$target_home/.config/openbox/autostart" <<'EOF'
#!/bin/sh

tint2 >/dev/null 2>&1 &
EOF

    chmod 755 "$target_home/.config/openbox/autostart"

    chown "$target_user:$target_user" \
        "$target_home/.xinitrc" \
        "$target_home/.config/openbox" \
        "$target_home/.config/openbox/autostart"
}

install_file_managers() {
    local package_name
    for package_name in "$@"; do
        case "$package_name" in
            pcmanfm) install_packages pcmanfm ;;
            doublecmd-gtk) install_packages doublecmd-gtk ;;
        esac
    done
}
install_task_tools() {
    local package_name
    for package_name in "$@"; do
        case "$package_name" in
            htop) install_packages htop ;;
            lxtask) install_packages lxtask ;;
        esac
    done
}
install_wallpaper_tools() {
    local package_name
    for package_name in "$@"; do
        case "$package_name" in
            nitrogen) install_packages nitrogen ;;
            feh) install_packages feh ;;
        esac
    done
}
install_network_tools() {
    if [[ "$1" == gui ]]; then
        install_packages network-manager network-manager-gnome
    fi
    if [[ "$2" == wireguard ]]; then
        install_packages wireguard wireguard-tools
    fi
}

install_brave() {
    local flavor="$1"
    case "$(dpkg --print-architecture)" in amd64|arm64) ;; *) printf '\nBrave can only be installed on amd64 and arm64 Debian systems.\n'; return 0 ;; esac
    if [[ "$flavor" == origin ]]; then printf '\nInstalling Brave Origin...\n'; curl -fsS https://dl.brave.com/install.sh | FLAVOR=origin sh; else printf '\nInstalling Brave Browser...\n'; curl -fsS https://dl.brave.com/install.sh | sh; fi
}

install_browser_choices() {
    local browser
    for browser in "$@"; do
        case "$browser" in
            brave) install_brave release ;;
            brave-origin) install_brave origin ;;
        esac
    done
}

automatic_install() {
    install_core
    install_lightdm
    install_file_managers doublecmd-gtk pcmanfm
    install_task_tools htop
    install_browser_choices brave-origin
    configure_openbox
}

custom_install() {
    local file_choices=() task_choices=() wallpaper_choices=() browser_choices=()
    local network_gui=no wireguard_choice=no lightdm_choice=no
    ask_yes_no "Install and enable LightDM as the default display manager?" && lightdm_choice=yes
    install_core
    [[ "$lightdm_choice" == yes ]] && install_lightdm

    choose_multiple "File managers" pcmanfm doublecmd-gtk
    file_choices=("${CHOICES[@]}")
    choose_multiple "Task managers" htop lxtask
    task_choices=("${CHOICES[@]}")
    if ask_yes_no "Install a wallpaper manager?"; then choose_multiple "Wallpaper managers" nitrogen feh; wallpaper_choices=("${CHOICES[@]}"); fi
    if ask_yes_no "Install a browser?"; then choose_multiple "Browsers" brave brave-origin; browser_choices=("${CHOICES[@]}"); fi
    ask_yes_no "Install the graphical NetworkManager applet?" && network_gui=gui
    ask_yes_no "Install WireGuard?" && wireguard_choice=wireguard
    install_file_managers "${file_choices[@]}"
    install_task_tools "${task_choices[@]}"
    install_wallpaper_tools "${wallpaper_choices[@]}"
    install_browser_choices "${browser_choices[@]}"
    install_network_tools "$network_gui" "$wireguard_choice"
    configure_openbox
}

main() {
    require_root
    is_debian || die "This script is designed for Debian or Debian-based systems."
    command -v apt-get >/dev/null 2>&1 || die "apt-get was not found."
    ask_yes_no "Use the -y option for apt installations?" && APT_ARGS=(-y)
    printf '\nDebiLite\n1) Automatic installation\n2) Custom installation\n3) Exit\n'
    local mode
    while true; do
        read -r -p "Choose [1-3]: " mode
        case "$mode" in 1) automatic_install; break ;; 2) custom_install; break ;; 3) exit 0 ;; *) printf 'Invalid choice.\n' ;; esac
    done
    printf '\nInstallation complete. Start Openbox with: startx\n'
}

main "$@"
