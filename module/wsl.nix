{ config, lib, pkgs, ... }:

# WSL2-specific tweaks for fido passthrough, networking, and compliance.

lib.mkIf config.modules.nixtune.wsl (let
  cfg = config.modules.nixtune;
  user = cfg.localUser;
in {
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
  boot.kernelModules = [ "usbip-core" "vhci-hcd" ];
})
