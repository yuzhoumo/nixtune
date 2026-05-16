# WSL Setup Guide

End-to-end guide for running nixtune on NixOS under WSL2, including disk
encryption and FIDO2 key passthrough from the Windows host.

## Prerequisites

- Windows 10 (22H2+) or Windows 11
- [WSL2 enabled](https://learn.microsoft.com/en-us/windows/wsl/install)
- A FIDO2 security key (e.g. YubiKey)
- Administrator access on the Windows host

---

## 1. Install NixOS-WSL

[NixOS-WSL](https://github.com/nix-community/NixOS-WSL) provides NixOS as a
first-class WSL2 distribution.

Follow the quick start guide: [NixOS-WSL Quickstart](https://nix-community.github.io/NixOS-WSL/)

---

## 2. Create your flake configuration

Create a flake that imports nixtune. This example assumes your WSL distro is
named `NixOS` and your local username is `myuser`:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixtune = {
      url = "github:yuzhoumo/nixtune";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixos-wsl, nixtune, ... }: {
    nixosConfigurations.wsl = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-wsl.nixosModules.default
        nixtune.nixosModules.default
        {
          wsl.enable = true;
          networking.hostName = "myhost";

          # Create your local user
          users.users.myuser = {
            isNormalUser = true;
            extraGroups = [ "wheel" ];
          };

          # nixtune config
          modules.nixtune = {
            localUser = "myuser";
            entraUser = "myuser@microsoft.com";
            wsl = true;
          };
        }
      ];
    };
  };
}
```

Apply the configuration:

```bash
sudo nixos-rebuild switch --flake .#wsl
```

---

## 3. Disk Encryption

This satisfies the Intune disk-encryption compliance policy.

Technically, this setup will work even if you skip encryption, since the policy
only checks for a non-empty `/etc/crypttab` file, which we have stubbed in the
WSL tweaks (because WSL doesn't support native linux encryption).

However, you should still encrypt your drive to remain in good-faith compliance
with the policy.

### Encrypting the WSL disk with `wsl --manage`

```powershell
# From an administrator PowerShell prompt, shut down the distro first
wsl --shutdown

# Encrypt the distro's VHDX (the distro name must match what you used during import)
wsl --manage NixOS --set-encryption on
```

You will be prompted to set a passphrase. This passphrase is required every time
the distro starts.

### Verify encryption status

```powershell
wsl --manage NixOS --get-encryption
```

The output should show `encrypted: true`.

### Notes

- The passphrase is separate from your NixOS user password.
- If you forget the passphrase, the VHDX data is unrecoverable.
- Alternatively, you can enable system-wide BitLocker on the Windows drive that
  holds the VHDX. Both approaches satisfy the compliance check.

---

## 4. USB/IP: FIDO key passthrough with usbipd-win

WSL2 does not have native USB access. The
[usbipd-win](https://github.com/dorssel/usbipd-win) project bridges USB
devices from the Windows host into the WSL2 VM over IP.

### Install usbipd-win on Windows

```powershell
# Using winget (recommended)
winget install usbipd
```

Or download the latest `.msi` from the
[usbipd-win releases](https://github.com/dorssel/usbipd-win/releases) page.

### Identify your FIDO key

With the security key plugged in:

```powershell
usbipd list
```

Look for your device: YubiKeys typically show vendor ID `1050`. Note the
**BUSID** (commands below will use `2-3` as an example).

### Bind and attach

```powershell
# Bind the device (one-time, persists across reboots)
usbipd bind --busid 2-3

# Attach to the WSL distro
usbipd attach --wsl --busid 2-3
```

### Verify inside NixOS

```bash
# The device should appear
lsusb
```

If the device doesn't show up, make sure the `vhci-hcd` module is loaded:

```bash
lsmod | grep vhci
```

The nixtune WSL module loads this automatically via a systemd oneshot service,
but you can also load it manually with `sudo modprobe vhci-hcd`.

### Detach when done

```powershell
usbipd detach --busid 2-3
```

---

## 5. Enroll in Intune

With everything in place, enroll the device:

```bash
sudo aad-tool auth-test --name myuser@microsoft.com
```

- When prompted for a Hello PIN, set it to the **same password** as your local
  NixOS user (this enables automatic unseal on login).
- Authenticate with your FIDO2 key when prompted.

Verify enrollment at https://portal.manage-beta.microsoft.com/devices.
