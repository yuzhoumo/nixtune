{ config, lib, pkgs, himmelblau, ... }:

# Himmelblau Entra ID / Intune enrollment for NixOS (user-mapping mode)
#
# This module configures himmelblau for the "register" join type, where a local
# user is mapped to an Entra ID identity rather than using Entra ID as the
# primary login.
#
# PAM is configured for unlock-only: himmelblau does NOT handle login
# authentication (pam_unix does that). Instead, a try_unseal rule runs after
# local auth to auto-unseal the Entra broker secrets using the login password.
#
# After deploying this configuration:
#   1. Rebuild: sudo nixos-rebuild switch --flake .#wsl-work
#   2. Enroll:  sudo aad-tool auth-test --name <entraUser>
#      - Set the Hello PIN to the SAME password as your local user.
#      - Authenticate with your FIDO2 key when prompted.
#   3. Verify:  check https://portal.manage-beta.microsoft.com/devices

let
  cfg = config.modules.himmelblau;
in
{
  imports = [
    himmelblau.nixosModules.himmelblau
    ./packages.nix
    ./compliance.nix
    ./wsl.nix
  ];

  options.modules.himmelblau = {
    localUser = lib.mkOption {
      type = lib.types.str;
      description = "Local username to map to the Entra ID identity.";
      example = "joemo";
    };

    entraUser = lib.mkOption {
      type = lib.types.str;
      description = "Entra ID UPN (email) to map the local user to.";
      example = "joemo@microsoft.com";
    };

    wsl = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this host runs under WSL2. Enables IPv6 workarounds, USB/IP FIDO passthrough, and other WSL-specific fixups.";
    };
  };

  config = {
    services.himmelblau = {
      enable = true;

      # User-mapping mode: himmelblau PAM on login/systemd-user for try_unseal
      # (auto-unlock Entra secrets with login password), NOT for interactive auth.
      pamServices = [ "login" "systemd-user" ];

      settings = {
        domain = [ "microsoft.com" ];
        join_type = "register";
        user_map_file = "/etc/himmelblau/user-map";
        enable_hello = true;
        enable_experimental_passwordless_fido = true;
        enable_experimental_mfa = true;
        hsm_type = "tpm_bound_soft_if_possible";
        ip_version = "ipv4-only";
        local_groups = [ "users" ];
        home_attr = "cn";
        home_alias = "cn";
        use_etc_skel = true;
      };
    };

    # User-mapping mode does NOT use nss-himmelblau. The upstream module
    # unconditionally adds "himmelblau" to nssDatabases, which causes
    # lookups for unknown names to hang (blocking sudo, aad-tool, etc.).
    system.nssDatabases.passwd = lib.mkForce [ "files" "systemd" ];
    system.nssDatabases.group = lib.mkForce [ "files" "[success=merge]" "systemd" ];
    system.nssDatabases.shadow = lib.mkForce [ "files" ];

    # Disable auth/account (would hang). Add try_unseal after pam_unix so
    # Entra secrets are automatically unlocked on local login.
    security.pam.services = let
      himmelblauPamLib = "${config.services.himmelblau.pamPackage.lib}/lib/libpam_himmelblau.so";
      overrides = svc: {
        rules.auth.himmelblau.enable = false;
        rules.account.himmelblau.enable = false;
        rules.auth.himmelblau-unseal = {
          order = config.security.pam.services.${svc}.rules.auth.unix.order + 1000;
          control = "optional";
          modulePath = himmelblauPamLib;
          settings.try_unseal = true;
        };
      };
    in lib.genAttrs [ "sudo" "login" "systemd-user" ] overrides;

    # User to Entra ID mapping
    environment.etc."himmelblau/user-map" = {
      text = "${cfg.localUser}:${cfg.entraUser}\n";
      mode = "0644";
    };

    # Enable lingering so systemd --user starts at boot (needed for
    # himmelblau-broker D-Bus service and linux-entra-sso)
    users.users.${cfg.localUser}.linger = true;
  };
}
