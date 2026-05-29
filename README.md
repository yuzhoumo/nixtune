# nixtune

NixOS module for Entra ID / Intune enrollment using
[himmelblau](https://github.com/himmelblau-idm/himmelblau) in
**user-mapping mode**.

This module configures himmelblau for the `register` join type, where a local
user is mapped to an Entra ID identity rather than using Entra ID as the
primary login. It includes patches for upstream bugs, compliance fixes for
MSIT conditional access on NixOS, and first-class WSL2 support.

## Options

| Option                      | Type   | Default | Description                                                         |
|-----------------------------|--------|---------|---------------------------------------------------------------------|
| `modules.nixtune.enable`    | bool   | `false` | Whether to enable nixtune Entra ID / Intune enrollment              |
| `modules.nixtune.localUser` | string | N/A     | Local username to map to the Entra ID identity                      |
| `modules.nixtune.entraUser` | string | N/A     | Entra ID UPN (email) to map the local user to                       |
| `modules.nixtune.wsl`       | bool   | `false` | Enable WSL2-specific fixups (IPv6, FIDO passthrough, crypttab stub) |


## Usage

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixtune = {
      url = "github:yuzhoumo/nixtune";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixtune, ... }: {
    nixosConfigurations.wsl = nixpkgs.lib.nixosSystem {
      modules = [
        nixtune.nixosModules.default
        {
          networking.hostName = "myhost";

          # Create your local user
          users.users.myuser = {
            isNormalUser = true;
            extraGroups = [ "wheel" ];
          };

          # nixtune config
          modules.nixtune = {
            enable = true;
            localUser = "myuser";
            entraUser = "myuser@microsoft.com";
          };
        }
      ];
    };
  };
}
```

Enroll: `sudo aad-tool auth-test --name <entraUser>`
  - Set the Hello PIN to the **same password** as your local user.
  - Authenticate with your FIDO2 key when prompted.

## Setup Guides

- **Bare-metal / VM**: For a complete guide to running nixtune on a standard
  NixOS installation see **[docs/setup.md](docs/setup.md)**.
- **WSL2**: For running nixtune on NixOS under WSL2 see
  **[docs/wsl-setup.md](docs/wsl-setup.md)**. Note: This is for joining the
  WSL2 NixOS instance itself (not necessary if the Windows host is joined). Use
  this option if your Windows host OS is using a personal account.

## Included Patches

These included patches fix issues in the upstream repositories:

- **kanidm-hsm-crypto**: Strip empty `extensionRequest` attribute from CSRs that Microsoft's Intune API rejects.
- **libhimmelblau**: PEM-wrap CSRs for Intune enroll API; log response bodies on API errors; fallback manufacturer for WSL/no-DMI systems.
- **aad-tool**: Resolve local usernames via `user_map_file` in `auth-test`, so user-mapping mode works without a domain suffix.
- **himmelblau_policies**: Read `authority_host` / `tenant_id` / `graph_url` from config instead of passing `None`.
