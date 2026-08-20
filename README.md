# DebiLite

**DebiLite** is a lightweight post-installation script for Debian that transforms a minimal, command-line-only Debian installation into a functional desktop system while keeping resource usage as low as possible.

The key idea is simple:

> **Start with a minimal Debian installation. Install only the standard system utilities. Let DebiLite install everything else.**

DebiLite is designed for low-spec computers, older hardware, and lightweight virtual machines where a conventional Debian desktop installation would use more resources than necessary.

## Features

* Lightweight graphical desktop
* Web browser
* File manager
* Minimal package selection
* Designed with low RAM usage in mind
* Suitable for older and low-spec hardware
* Suitable for virtual machines
* Automated installation and configuration

## Requirements

Before running DebiLite, you need:

* A minimal Debian installation
* Root access
* An active Internet connection
* `git`
* Sufficient disk space for the packages installed by DebiLite

A Debian **netinst** installation is recommended.

## Important: Debian Installation

DebiLite **must be installed on a minimal Debian system**.

During the Debian installation, when the **Software selection** screen appears:

### Select ONLY:

* **Standard system utilities**

### Do NOT select:

* Debian desktop environment
* GNOME
* Xfce
* KDE Plasma
* Cinnamon
* MATE
* LXDE
* LXQt
* Web server
* SSH server
* Any other optional software

In other words, **the only selected item should be `Standard system utilities`.**

DebiLite installs the graphical environment and desktop applications itself after the base Debian installation has finished.

This is important because installing a desktop environment during the Debian installation defeats the purpose of DebiLite and can result in unnecessary packages and higher resource usage.

## Installing Debian

Download the Debian netinst image from the official Debian website:

[Debian](https://www.debian.org/?utm_source=chatgpt.com)

Boot the installer and perform a normal Debian installation.

You can use the installer's standard options for:

1. Language
2. Location
3. Keyboard layout
4. Network configuration
5. Hostname
6. Root password
7. User account
8. Partitioning
9. Debian package mirror
10. GRUB installation

When the installer reaches **Software selection**, make sure that **only `Standard system utilities` is selected**.

Complete the Debian installation and reboot into the newly installed system.

At this point, the system should still be a **command-line-only Debian installation**.

## Installing DebiLite

Log in as `root`.

Update the package lists:

```bash
apt-get update
```

Install Git:

```bash
apt-get install git
```

Clone the repository:

```bash
cd /root
git clone https://github.com/zoardgodor/DebiLite.git
```

Enter the repository:

```bash
cd DebiLite
```

Make the installer executable:

```bash
chmod +x DebiLite.sh
```

Run DebiLite:

```bash
./DebiLite.sh
```

The installer will guide you through the remaining installation process.

After the installer has finished, reboot the system:

```bash
reboot
```

## How DebiLite Works

DebiLite intentionally separates the Debian installation from the desktop installation.

The process is:

```text
Debian netinst
     │
     ▼
Minimal Debian installation
     │
     │  Only "Standard system utilities"
     ▼
Command-line-only system
     │
     │  DebiLite.sh
     ▼
Desktop + browser + file manager
     │
     ▼
Lightweight usable Debian system
```

The Debian installer itself is **not** used to install the desktop environment.

Instead, DebiLite performs the required installation and configuration afterwards.

## Why Start Without a Desktop?

A standard Debian desktop installation can pull in a large number of packages and services that may not be necessary for a lightweight system.

DebiLite starts from a clean, minimal system so that the script has direct control over what gets installed.

This helps keep the resulting installation:

* Smaller
* Simpler
* More predictable
* Better suited to low-resource hardware

## RAM Usage

Low memory consumption is one of DebiLite's primary goals.

The project targets approximately:

**~200 MB RAM at idle**

However, this number is **not a guaranteed system requirement or fixed measurement**.

Actual RAM usage depends on factors such as:

* Debian version
* Installed packages
* Desktop environment
* Display manager
* Graphics drivers
* Kernel
* Hardware
* Virtualization
* Background services

For this reason, the ~200 MB figure should be considered a target rather than a guaranteed value.

## Virtual Machines

DebiLite can be used in virtual machines as well as on physical hardware.

When installing Debian in a VM:

* Disable unattended installation.
* Use the Debian netinst image.
* Install only `Standard system utilities`.
* Make sure the guest has Internet access.
* Run DebiLite after the Debian installation has completed.

The host machine must also have a working Internet connection if the virtual machine accesses the Internet through the host.

## Important Warning

**DebiLite is intended to modify the system on which it is executed.**

The installer is normally run as `root` and may install packages, modify configuration files, enable services, and make other system-level changes.

Do not run it on an important production system without first testing it.

If you want to understand exactly what DebiLite does, inspect `DebiLite.sh` before running it.

## Troubleshooting

### `git` is not installed

Run:

```bash
apt-get update
apt-get install git
```

### The repository cannot be cloned

Check your Internet connection:

```bash
ping -c 3 deb.debian.org
```

Then try cloning the repository again.

### The script cannot be executed

Run:

```bash
chmod +x DebiLite.sh
```

Then:

```bash
./DebiLite.sh
```

### The installation fails

If the installer fails, provide the following when reporting the issue:

* Debian version
* CPU architecture
* Physical machine or virtual machine
* Virtualization software, if applicable
* The command that was executed
* The complete error message
* Relevant output from `DebiLite.sh`

## Compatibility

DebiLite is intended for Debian systems installed from the Debian netinst image.

The recommended installation starts with:

> **Only `Standard system utilities` selected in Debian's Software selection screen.**

Desktop environments and other optional software should **not** be pre-installed.

Tested Debian releases should be documented here as the project develops.

## Development

The main installer is:

```text
DebiLite.sh
```

When modifying DebiLite, test the script on a fresh Debian installation with **only `Standard system utilities` installed**.

This is important because testing on an already-configured desktop system does not accurately represent the environment DebiLite is designed for.

## Contributing

Contributions and bug reports are welcome.

Before submitting changes:

1. Test the installer on a clean Debian installation.
2. Use only `Standard system utilities` during the Debian installation.
3. Test the complete installation from start to finish.
4. Avoid unnecessary dependencies.
5. Keep the resulting system lightweight.
6. Document any changes that affect installed packages or system configuration.

## License

See the repository for the project's license information.

---

**DebiLite — start with a minimal Debian system, then build only the desktop you need.**

