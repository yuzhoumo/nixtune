{ config, lib, pkgs, ... }:

# On NixOS, several things don't match what MSIT expects for compliance:
#
# 1. OS identity:     Spoof /etc/os-release to fake Ubuntu.
# 2. FHS dirs:        NixOS FHS directories are default read-only. We need to
#                     explicitly specify writeable directories.
# 3. Sandbox gaps:    The upstream systemd unit restricts AF_UNIX only and
#                     has ProtectSystem=strict, blocking network + file writes
#                     that policy enforcement needs.
# 4. Cron:            Enable cron service for Intune script policies.

{
  # MSIT conditional-access policy requires Ubuntu. We write a fake
  # os-release and bind-mount it into the tasks daemon's mount namespace.
  environment.etc."himmelblau/fake-os-release" = {
    text = ''
      PRETTY_NAME="Ubuntu 22.04.4 LTS"
      NAME="Ubuntu"
      VERSION_ID="22.04"
      VERSION="22.04.4 LTS (Jammy Jellyfish)"
      VERSION_CODENAME=jammy
      ID=ubuntu
      ID_LIKE=debian
      HOME_URL="https://www.ubuntu.com/"
      SUPPORT_URL="https://help.ubuntu.com/"
      BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
      PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
      UBUNTU_CODENAME=jammy
    '';
    mode = "0444";
  };

  # Bind-mount the fake os release paths for himmelblaud-tasks
  systemd.services.himmelblaud-tasks.serviceConfig.BindReadOnlyPaths = [
    "/etc/himmelblau/fake-os-release:/etc/os-release"
    "/etc/himmelblau/fake-os-release:/usr/lib/os-release"
  ];

  # Enable cron service since Intune script policies install cron jobs
  services.cron.enable = true;

  # Writeable FHS directories for himmelblau (since NixOS is default read-only)
  systemd.tmpfiles.rules = [
    "d /etc/cron.d 0755 root root -"                    # cron jobs
    "d /etc/krb5.conf.d 0755 root root -"               # kerberos config
    "d /var/cache/himmelblau-policies 0750 root root -" # policy script cache
    "d /var/lib/AccountsService/icons 0755 root root -" # icons
    "d /var/lib/AccountsService/users 0755 root root -" # profile pictures
  ];

  # The upstream unit sets RestrictAddressFamilies=AF_UNIX and
  # ProtectSystem=strict. Policy enforcement needs:
  #   - AF_INET for HTTPS to Graph/Intune APIs
  #   - Write access to policy cache, cron, kerberos, profile photos
  systemd.services.himmelblaud-tasks.serviceConfig = {
    RestrictAddressFamilies = lib.mkForce "AF_UNIX AF_INET";
    ReadWritePaths = [
      "/etc/cron.d"
      "/etc/krb5.conf.d"
      "/var/cache/himmelblau-policies"
      "/var/lib/AccountsService"
    ];
  };
}
