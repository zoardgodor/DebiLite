```bash
#!/usr/bin/env bash
set -Eeuo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

APT_UPDATED=0
APT_ARGS=()

die() {
    printf '\nError: %s\n' "$1" >&2
    exit 1
}

info() {
    printf '\n[DebiLite] %s\n' "$1"
}

require_root() {
    [[ "$(id -u)" -eq 0 ]] || die "Run this installer as root. Example: sudo bash DebiLite.sh"
}

is_debian() {
    [[ -r /etc/os-release ]] || return 1
    . /etc/os-release
    [[ "${ID:-}" == "debian" || "${ID_LIKE:-}" == *debian* ]]
}

package_installed() {
    dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null | grep -qx installed
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

apt_update() {
    [[ "$APT_UPDATED" -eq 1 ]] && return 0

    printf '\nUpdating package lists...\n'
    apt-get update
    APT_UPDATED=1
}

install_packages() {
    local missing=()
    local package_name

    for package_name in "$@"; do
        package_installed "$package_name" || missing+=("$package_name")
    done

    [[ "${#missing[@]}" -eq 0 ]] && return 0

    apt_update

    printf '\nInstalling: %s\n' "${missing[*]}"

    apt-get install \
        "${APT_ARGS[@]}" \
        --no-install-recommends \
        "${missing[@]}"
}

ask_yes_no() {
    local question="$1"
    local default_answer="${2:-n}"
    local answer

    if [[ "$default_answer" == "y" ]]; then
        read -r -p "$question [Y/n]: " answer
        [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]
    else
        read -r -p "$question [y/N]: " answer
        [[ "$answer" =~ ^[Yy]$ ]]
    fi
}

choose_multiple() {
    local title="$1"
    shift

    local options=("$@")
    local answer
    local item
    local index

    printf '\n%s\n' "$title"

    for index in "${!options[@]}"; do
        printf '%s) %s\n' "$((index + 1))" "${options[$index]}"
    done

    printf 'Separate multiple choices with commas or spaces.\n'
    printf 'Empty answer: none.\n'

    read -r -p "Choose: " answer

    answer="${answer//,/ }"
    CHOICES=()

    for item in $answer; do
        if [[ "$item" =~ ^[0-9]+$ ]] &&
           [[ "$item" -ge 1 ]] &&
           [[ "$item" -le "${#options[@]}" ]]; then
            CHOICES+=("${options[$((item - 1))]}")
        fi
    done
}

ensure_terminal() {
    local terminal

    for terminal in \
        xterm \
        xfce4-terminal \
        lxterminal \
        sakura \
        alacritty \
        foot \
        konsole \
        gnome-terminal
    do
        command_exists "$terminal" && return 0
    done

    install_packages xterm
}

install_lightdm() {
    install_packages lightdm lightdm-gtk-greeter

    if command_exists debconf-set-selections; then
        printf '%s\n' \
            'lightdm shared/default-x-display-manager select /usr/sbin/lightdm' |
            debconf-set-selections
    fi

    if command_exists systemctl; then
        systemctl unmask lightdm.service >/dev/null 2>&1 || true
        systemctl enable lightdm.service >/dev/null 2>&1 || true
        systemctl set-default graphical.target >/dev/null 2>&1 || true
    fi

    if [[ -d /etc/systemd/system ]] &&
       [[ -e /lib/systemd/system/lightdm.service ]]; then
        ln -sfn \
            /lib/systemd/system/lightdm.service \
            /etc/systemd/system/display-manager.service

        ln -sfn \
            /lib/systemd/system/graphical.target \
            /etc/systemd/system/default.target
    fi
}

install_core() {
    install_packages \
        sudo \
        nano \
        curl \
        ca-certificates \
        wget \
        gnupg \
        debconf \
        bash \
        coreutils \
        util-linux \
        procps \
        iproute2 \
        iputils-ping \
        grep \
        sed \
        gawk \
        findutils \
        less \
        file \
        dbus-x11 \
        xorg \
        xinit \
        x11-xserver-utils \
        openbox \
        obconf \
        tint2 \
        nitrogen \
        pcmanfm \
        mousepad \
        menu

    ensure_terminal
}

install_file_managers() {
    local package_name

    for package_name in "$@"; do
        case "$package_name" in
            pcmanfm)
                install_packages pcmanfm
                ;;
            doublecmd-gtk)
                install_packages doublecmd-gtk
                ;;
        esac
    done
}

install_task_tools() {
    local package_name

    for package_name in "$@"; do
        case "$package_name" in
            htop)
                install_packages htop
                ;;
            lxtask)
                install_packages lxtask
                ;;
        esac
    done
}

install_wallpaper_tools() {
    local package_name

    for package_name in "$@"; do
        case "$package_name" in
            nitrogen)
                install_packages nitrogen
                ;;
            feh)
                install_packages feh
                ;;
        esac
    done
}

install_network_tools() {
    if [[ "${1:-}" == "gui" ]]; then
        install_packages network-manager network-manager-gnome
    fi

    if [[ "${2:-}" == "wireguard" ]]; then
        install_packages wireguard wireguard-tools
    fi
}

install_brave() {
    local flavor="$1"

    case "$(dpkg --print-architecture)" in
        amd64|arm64)
            ;;
        *)
            printf '\nBrave can only be installed on amd64 and arm64 Debian systems.\n'
            return 0
            ;;
    esac

    if [[ "$flavor" == "origin" ]]; then
        printf '\nInstalling Brave Origin...\n'
        curl -fsS https://dl.brave.com/install.sh | FLAVOR=origin sh
    else
        printf '\nInstalling Brave Browser...\n'
        curl -fsS https://dl.brave.com/install.sh | sh
    fi
}

install_browser_choices() {
    local browser

    for browser in "$@"; do
        case "$browser" in
            brave)
                install_brave release
                ;;
            brave-origin)
                install_brave origin
                ;;
        esac
    done
}

find_desktop_user() {
    local current_user
    local uid
    local home

    if [[ -n "${SUDO_USER:-}" ]] &&
       [[ "${SUDO_USER}" != "root" ]] &&
       id "$SUDO_USER" >/dev/null 2>&1; then

        DESKTOP_USER="$SUDO_USER"
        DESKTOP_HOME="$(getent passwd "$DESKTOP_USER" | cut -d: -f6)"

        [[ -n "$DESKTOP_HOME" ]] && return 0
    fi

    while IFS=: read -r current_user _ uid _ _ home _; do
        if [[ "$uid" -ge 1000 ]] &&
           [[ "$uid" -lt 60000 ]] &&
           [[ "$current_user" != "nobody" ]] &&
           [[ -d "$home" ]]; then

            DESKTOP_USER="$current_user"
            DESKTOP_HOME="$home"

            return 0
        fi
    done < /etc/passwd

    return 1
}

create_user_config() {
    local target_user="$1"
    local target_home="$2"

    local config_dir="$target_home/.config"
    local openbox_dir="$config_dir/openbox"
    local tint2_dir="$config_dir/tint2"
    local nitrogen_dir="$config_dir/nitrogen"
    local wallpaper_dir="$target_home/Pictures/Wallpapers"

    mkdir -p \
        "$openbox_dir" \
        "$tint2_dir" \
        "$nitrogen_dir" \
        "$wallpaper_dir"

    cat > "$target_home/.xinitrc" <<'EOF'
#!/bin/sh

if command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session -- openbox-session
else
    exec openbox-session
fi
EOF

    chmod 755 "$target_home/.xinitrc"

    cat > "$openbox_dir/autostart" <<'EOF'
#!/bin/sh

if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP DESKTOP_SESSION >/dev/null 2>&1 || true
fi

if command -v nitrogen >/dev/null 2>&1; then
    nitrogen --restore >/dev/null 2>&1 &
elif command -v feh >/dev/null 2>&1; then
    if [ -f "$HOME/Pictures/Wallpapers/debilite.svg" ]; then
        feh --bg-fill "$HOME/Pictures/Wallpapers/debilite.svg" >/dev/null 2>&1 &
    fi
fi

if command -v tint2 >/dev/null 2>&1; then
    tint2 >/dev/null 2>&1 &
fi

if command -v nm-applet >/dev/null 2>&1; then
    nm-applet >/dev/null 2>&1 &
fi
EOF

    chmod 755 "$openbox_dir/autostart"

    cat > "$openbox_dir/menu.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>

<openbox_menu xmlns="http://openbox.org/3.4/menu">

  <menu id="root-menu" label="DebiLite">

    <item label="Terminal">
      <action name="Execute">
        <command>x-terminal-emulator</command>
      </action>
    </item>

    <item label="File Manager">
      <action name="Execute">
        <command>pcmanfm</command>
      </action>
    </item>

    <item label="Text Editor">
      <action name="Execute">
        <command>mousepad</command>
      </action>
    </item>

    <separator />

    <item label="Openbox Configuration">
      <action name="Execute">
        <command>obconf</command>
      </action>
    </item>

    <item label="Wallpaper">
      <action name="Execute">
        <command>nitrogen</command>
      </action>
    </item>

    <separator />

    <item label="Restart Openbox">
      <action name="Restart" />
    </item>

    <item label="Exit Openbox">
      <action name="Exit" />
    </item>

  </menu>

</openbox_menu>
EOF

    cat > "$openbox_dir/rc.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>

<openbox_config xmlns="http://openbox.org/3.6/rc">

  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>

  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <focusLast>yes</focusLast>
    <underMouse>no</underMouse>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>

  <placement>
    <policy>Smart</policy>
    <center>yes</center>
  </placement>

  <theme>
    <name>Clearlooks</name>
    <titleLayout>NLIMC</titleLayout>

    <font place="ActiveWindow">
      <name>Sans</name>
      <size>10</size>
      <weight>Bold</weight>
    </font>

    <font place="InactiveWindow">
      <name>Sans</name>
      <size>10</size>
      <weight>Normal</weight>
    </font>

    <font place="MenuHeader">
      <name>Sans</name>
      <size>10</size>
      <weight>Bold</weight>
    </font>

    <font place="MenuItem">
      <name>Sans</name>
      <size>10</size>
      <weight>Normal</weight>
    </font>
  </theme>

  <desktops>
    <number>4</number>
    <firstdesk>1</firstdesk>

    <names>
      <name>Desktop 1</name>
      <name>Desktop 2</name>
      <name>Desktop 3</name>
      <name>Desktop 4</name>
    </names>

    <popupTime>875</popupTime>
  </desktops>

  <resize>
    <drawContents>yes</drawContents>
    <popupShow>Nonpixel</popupShow>
    <popupPosition>Center</popupPosition>
  </resize>

  <margins>
    <top>0</top>
    <bottom>0</bottom>
    <left>0</left>
    <right>0</right>
  </margins>

  <keyboard>

    <keybind key="W-Return">
      <action name="Execute">
        <command>x-terminal-emulator</command>
      </action>
    </keybind>

    <keybind key="W-e">
      <action name="Execute">
        <command>pcmanfm</command>
      </action>
    </keybind>

    <keybind key="W-r">
      <action name="Execute">
        <command>obconf</command>
      </action>
    </keybind>

    <keybind key="W-m">
      <action name="ShowMenu">
        <menu>root-menu</menu>
      </action>
    </keybind>

    <keybind key="W-d">
      <action name="ToggleShowDesktop" />
    </keybind>

    <keybind key="W-Left">
      <action name="DesktopLeft">
        <wrap>yes</wrap>
      </action>
    </keybind>

    <keybind key="W-Right">
      <action name="DesktopRight">
        <wrap>yes</wrap>
      </action>
    </keybind>

    <keybind key="W-1">
      <action name="GoToDesktop">
        <desktop>1</desktop>
      </action>
    </keybind>

    <keybind key="W-2">
      <action name="GoToDesktop">
        <desktop>2</desktop>
      </action>
    </keybind>

    <keybind key="W-3">
      <action name="GoToDesktop">
        <desktop>3</desktop>
      </action>
    </keybind>

    <keybind key="W-4">
      <action name="GoToDesktop">
        <desktop>4</desktop>
      </action>
    </keybind>

  </keyboard>

  <mouse>

    <context name="Root">
      <mousebind button="Right" action="Press">
        <action name="ShowMenu">
          <menu>root-menu</menu>
        </action>
      </mousebind>
    </context>

    <context name="Client">
      <mousebind button="Left" action="Press">
        <action name="Focus" />
        <action name="Raise" />
      </mousebind>

      <mousebind button="Left" action="Drag">
        <action name="Move" />
      </mousebind>

      <mousebind button="Right" action="Press">
        <action name="ShowMenu">
          <menu>client-menu</menu>
        </action>
      </mousebind>
    </context>

  </mouse>

</openbox_config>
EOF

    cat > "$tint2_dir/tint2rc" <<'EOF'
panel_items = TSC
panel_position = bottom center horizontal
panel_size = 100% 30
panel_margin = 0 0
panel_padding = 4 2 4
panel_background_id = 1
wm_menu = 1
wm_menu_tooltip = 1
taskbar_mode = multi_desktop
taskbar_padding = 2 2 2
taskbar_background_id = 1
task_icon = 1
task_text = 1
task_centered = 0
task_maximum_size = 200 30
task_background_id = 2
task_active_background_id = 3
task_urgent_background_id = 3
systray_padding = 2 0 2
systray_sort = ascending
systray_icon_size = 20
systray_icon_asb = 100 0 0
clock_format = %H:%M
clock_tooltip = %A %d %B %Y
clock_padding = 4 0
clock_background_id = 1
launcher_padding = 2 0 2
launcher_icon_size = 22
rounded = 0
border_width = 0
background_color = #222222 95
border_color = #000000 0
rounded = 3
border_width = 0
background_color = #333333 100
border_color = #000000 0
EOF

    cat > "$nitrogen_dir/bg-saved.cfg" <<EOF
[xin_-1]
file=$wallpaper_dir/debilite.svg
mode=5
bgcolor=#20242b
EOF

    cat > "$wallpaper_dir/debilite.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080">
<defs>
<linearGradient id="background" x1="0" y1="0" x2="1" y2="1">
<stop offset="0%" stop-color="#101820"/>
<stop offset="50%" stop-color="#202a35"/>
<stop offset="100%" stop-color="#111820"/>
</linearGradient>
<radialGradient id="glow">
<stop offset="0%" stop-color="#4c7899" stop-opacity="0.28"/>
<stop offset="100%" stop-color="#4c7899" stop-opacity="0"/>
</radialGradient>
</defs>
<rect width="1920" height="1080" fill="url(#background)"/>
<circle cx="1500" cy="250" r="500" fill="url(#glow)"/>
<circle cx="350" cy="850" r="450" fill="url(#glow)"/>
<text x="960" y="510" text-anchor="middle" fill="#ffffff" fill-opacity="0.90" font-family="sans-serif" font-size="72" font-weight="bold">DebiLite</text>
<text x="960" y="580" text-anchor="middle" fill="#ffffff" fill-opacity="0.45" font-family="sans-serif" font-size="26">Lightweight Debian + Openbox</text>
</svg>
EOF

    chown -R "$target_user:$target_user" \
        "$config_dir" \
        "$target_home/.xinitrc" \
        "$target_home/Pictures"

    chmod 700 "$config_dir"
    chmod 755 "$openbox_dir"
    chmod 755 "$tint2_dir"
    chmod 755 "$nitrogen_dir"
}

configure_desktop() {
    find_desktop_user ||
        die "No normal user account was found."

    create_user_config \
        "$DESKTOP_USER" \
        "$DESKTOP_HOME"
}

verify_installation() {
    local failed=0
    local package_name

    for package_name in \
        xorg \
        xinit \
        openbox \
        obconf \
        tint2 \
        nitrogen \
        pcmanfm \
        lightdm
    do
        if ! package_installed "$package_name"; then
            printf 'Missing package: %s\n' "$package_name"
            failed=1
        fi
    done

    [[ "$failed" -eq 0 ]] ||
        die "Desktop verification failed."

    [[ -f "$DESKTOP_HOME/.xinitrc" ]] ||
        die "Missing $DESKTOP_HOME/.xinitrc"

    [[ -f "$DESKTOP_HOME/.config/openbox/autostart" ]] ||
        die "Missing Openbox autostart."

    [[ -f "$DESKTOP_HOME/.config/openbox/rc.xml" ]] ||
        die "Missing Openbox configuration."

    [[ -f "$DESKTOP_HOME/.config/tint2/tint2rc" ]] ||
        die "Missing Tint2 configuration."

    [[ -f "$DESKTOP_HOME/.config/nitrogen/bg-saved.cfg" ]] ||
        die "Missing Nitrogen configuration."

    printf '\nDesktop verification successful.\n'
}

automatic_install() {
    install_core
    install_lightdm
    install_file_managers doublecmd-gtk pcmanfm
    install_task_tools htop
    install_browser_choices brave-origin
    configure_desktop
}

custom_install() {
    local file_choices=()
    local task_choices=()
    local wallpaper_choices=()
    local browser_choices=()
    local network_gui=no
    local wireguard_choice=no
    local lightdm_choice=no

    if ask_yes_no \
        "Install and enable LightDM as the default display manager?" \
        y
    then
        lightdm_choice=yes
    fi

    install_core

    if [[ "$lightdm_choice" == yes ]]; then
        install_lightdm
    fi

    choose_multiple \
        "File managers" \
        pcmanfm \
        doublecmd-gtk

    file_choices=("${CHOICES[@]}")

    choose_multiple \
        "Task managers" \
        htop \
        lxtask

    task_choices=("${CHOICES[@]}")

    if ask_yes_no "Install an additional wallpaper manager?"; then
        choose_multiple \
            "Wallpaper managers" \
            nitrogen \
            feh

        wallpaper_choices=("${CHOICES[@]}")
    fi

    if ask_yes_no "Install a browser?"; then
        choose_multiple \
            "Browsers" \
            brave \
            brave-origin

        browser_choices=("${CHOICES[@]}")
    fi

    if ask_yes_no "Install the graphical NetworkManager applet?"; then
        network_gui=gui
    fi

    if ask_yes_no "Install WireGuard?"; then
        wireguard_choice=wireguard
    fi

    install_file_managers "${file_choices[@]}"
    install_task_tools "${task_choices[@]}"
    install_wallpaper_tools "${wallpaper_choices[@]}"
    install_browser_choices "${browser_choices[@]}"
    install_network_tools "$network_gui" "$wireguard_choice"

    configure_desktop
}

main() {
    require_root
    is_debian || die "This script is designed for Debian or Debian-based systems."
    command_exists apt-get || die "apt-get was not found."
    check_dependencies

    if ask_yes_no "Use the -y option for apt installations?"; then
        APT_ARGS=(-y)
    fi

    printf '\nDebiLite %s\n' "2.0"
    printf '1) Automatic installation\n'
    printf '2) Custom installation\n'
    printf '3) Exit\n'

    local mode

    while true; do
        read -r -p "Choose [1-3]: " mode

        case "$mode" in
            1)
                automatic_install
                break
                ;;
            2)
                custom_install
                break
                ;;
            3)
                exit 0
                ;;
            *)
                printf 'Invalid choice.\n'
                ;;
        esac
    done

    verify_installation

    printf '\nInstallation complete.\n'
    printf 'Reboot the system and LightDM should start Openbox automatically.\n'
    printf 'Right click on the desktop for the Openbox menu.\n'
    printf 'Super+Return opens a terminal.\n'
    printf 'Super+E opens the file manager.\n'
    printf 'Super+R opens ObConf.\n'
}

main "$@"
```
