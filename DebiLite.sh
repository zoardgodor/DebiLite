#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
APT_UPDATED=0
APT_ARGS=()

die() { printf '\nError: %s\n' "$1" >&2; exit 1; }
require_root() { [[ "$(id -u)" -eq 0 ]] || die "Run this installer as root. Example: sudo bash DebiLite.sh"; }
is_debian() { [[ -r /etc/os-release ]] || return 1; . /etc/os-release; [[ "${ID:-}" == "debian" || "${ID_LIKE:-}" == *debian* ]]; }
package_installed() { dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null | grep -qx installed; }

internet_ok() {
    command -v curl >/dev/null 2>&1 && curl -fsS --connect-timeout 5 --max-time 12 https://deb.debian.org/ >/dev/null 2>&1 && return 0
    command -v wget >/dev/null 2>&1 && wget -q --timeout=8 --tries=1 --spider https://deb.debian.org/ && return 0
    return 1
}

start_network_manager() {
    command -v systemctl >/dev/null 2>&1 && systemctl start NetworkManager.service >/dev/null 2>&1 || true
    command -v service >/dev/null 2>&1 && service NetworkManager start >/dev/null 2>&1 || true
}

connect_network() {
    start_network_manager
    if command -v nmtui >/dev/null 2>&1; then
        printf '\nThe NetworkManager text interface will start. Use Activate a connection for visible Wi-Fi networks, or Edit a connection to add a hidden network.\n'
        nmtui || true
        return 0
    fi
    if command -v nmcli >/dev/null 2>&1; then
        printf '\nAvailable Wi-Fi networks:\n'
        nmcli device wifi list --rescan yes || true
        local ssid password hidden
        read -r -p "SSID (enter it for a hidden network too): " ssid
        [[ -n "$ssid" ]] || return 1
        read -r -s -p "Wi-Fi password (leave empty for an open network): " password
        printf '\n'
        read -r -p "Hidden network? [y/N]: " hidden
        if [[ "$hidden" =~ ^[Yy]$ ]]; then
            [[ -n "$password" ]] && nmcli device wifi connect "$ssid" password "$password" hidden yes || nmcli device wifi connect "$ssid" hidden yes
        elif [[ -n "$password" ]]; then
            nmcli device wifi connect "$ssid" password "$password"
        else
            nmcli device wifi connect "$ssid"
        fi
        return $?
    fi
    printf '\nNo usable network manager is available. Connect Ethernet before NetworkManager can be installed.\n'
    return 1
}

ensure_internet() {
    internet_ok && return 0
    while ! internet_ok; do
        printf '\nThere is no working internet connection. Press Enter to open the network interface. Quit: q.\n'
        local answer
        read -r -p "Continue? [Enter/q]: " answer
        [[ "$answer" =~ ^[Qq]$ ]] && die "An internet connection is required for installation."
        connect_network || true
        internet_ok || printf '\nThe connection is still not working.\n'
    done
}

apt_update() {
    [[ "$APT_UPDATED" -eq 1 ]] && return 0
    ensure_internet
    printf '\nUpdating package lists...\n'
    apt-get update
    APT_UPDATED=1
}

install_packages() {
    local missing=() package_name
    for package_name in "$@"; do package_installed "$package_name" || missing+=("$package_name"); done
    [[ "${#missing[@]}" -eq 0 ]] && return 0
    ensure_internet
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
    for index in "${!options[@]}"; do printf '%s) %s\n' "$((index + 1))" "${options[$index]"; done
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
        printf '%s\n' 'lightdm shared/default-x-display-manager select /usr/sbin/lightdm' | debconf-set-selections
    fi
    install_packages lightdm lightdm-gtk-greeter
    command -v systemctl >/dev/null 2>&1 && systemctl unmask lightdm.service >/dev/null 2>&1 || true
    command -v systemctl >/dev/null 2>&1 && systemctl enable lightdm.service >/dev/null 2>&1 || true
    command -v systemctl >/dev/null 2>&1 && systemctl set-default graphical.target >/dev/null 2>&1 || true
    if [[ -d /etc/systemd/system && -e /lib/systemd/system/lightdm.service ]]; then
        ln -sfn /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service
        ln -sfn /lib/systemd/system/graphical.target /etc/systemd/system/default.target
    fi
}

install_core() {
    install_packages sudo nano curl ca-certificates wget gnupg debconf bash coreutils util-linux procps iproute2 iputils-ping grep sed gawk findutils less file network-manager wpasupplicant rfkill openbox xorg xinit dbus-x11 mousepad
    ensure_terminal
    start_network_manager
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
        install_packages network-manager-gnome
        start_network_manager
    fi
    if [[ "$2" == wireguard ]]; then
        install_packages wireguard wireguard-tools
    fi
}

install_brave() {
    local flavor="$1"
    case "$(dpkg --print-architecture)" in amd64|arm64) ;; *) printf '\nBrave can only be installed on amd64 and arm64 Debian systems.\n'; return 0 ;; esac
    ensure_internet
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
