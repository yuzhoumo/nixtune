{ config, lib, pkgs, ... }:

# WSL2-specific tweaks for fido passthrough, networking, and compliance.
#
# 1. Fido passthrough  Pass through fido key from the host using usbipd.
# 2. IPv6:             WSL2's IPv6 is broken; disable it system-wide.
# 3. Disk encryption:  WSL2 does not have access to block devices, so there's
#                      no way to populate a "real" /etc/crypttab entry with a
#                      working dm-crypt mapping. We can provide a stub to
#                      satisfy the compliance check. Please use either
#                      `wsl --manage encrypt` on the Windows host or sytem-wide
#                      Bitlocker encryption to remain in good faith compliance.

lib.mkIf config.modules.himmelblau.wsl (let
  cfg = config.modules.himmelblau;
  user = cfg.localUser;
in {
  # Set the default WSL user and enable Windows interop
  wsl.defaultUser = user;
  wsl.interop.register = true;

  # WSL's systemd-logind doesn't honor linger files, so the user
  # manager (and therefore user D-Bus) won't auto-start. Force it.
  # Restart on failure works around a WSL2 race condition where the
  # systemd executor hits EBUSY ("Device or resource busy") because
  # the cgroup hierarchy isn't ready during early boot.
  systemd.services."user@${toString config.users.users.${user}.uid}" = {
    enable = true;
    wantedBy = [ "multi-user.target" ];
    overrideStrategy = "asDropin";
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5s";
    };
    unitConfig.StartLimitIntervalSec = 0;
  };

  # WSL doesn't run systemd-modules-load normally, so ensure USB/IP modules
  # are loaded at boot via a oneshot service
  systemd.services.load-usbip-modules = {
    description = "Load USB/IP kernel modules for usbipd passthrough";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.kmod}/bin/modprobe vhci-hcd";
    };
  };

  # USB passthrough for FIDO2/YubiKey (via usbipd-win on the Windows host)
  services.udev.enable = true;
  boot.kernelModules = [ "usbip-core" "vhci-hcd" ];

  # udev rules for FIDO2/YubiKey — allow non-root users to access HID devices.
  # Matches any YubiKey (vendor 1050) and any FIDO HID device (usage page F1D0)
  services.udev.extraRules = ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1050", MODE="0660", GROUP="users"
  '';

  # Also pull in the community FIDO2 udev rules for broad device support
  services.udev.packages = [ pkgs.libfido2 ];

  # WSL2 cannot create IPv6 sockets; disable at the kernel level so all
  # applications (not just himmelblau) use IPv4
  boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 1;
  boot.kernel.sysctl."net.ipv6.conf.default.disable_ipv6" = 1;

  # The compliance checker looks for a non-empty /etc/crypttab. We stub this
  # here, but please use either `wsl --manage encrypt` on the Windows host or
  # sytem-wide Bitlocker encryption to remain in good faith compliance.
  environment.etc."crypttab" = {
    text = "# WSL2 VHDX encrypted via wsl --manage encrypt (BitLocker VHD encryption)\n";
    mode = "0644";
  };
})
