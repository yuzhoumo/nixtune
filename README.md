# nixtune

NixOS module for Entra ID / Intune enrollment using
[himmelblau](https://github.com/himmelblau-idm/himmelblau) in
**user-mapping mode**, targeting Microsoft internal (MSIT) Intune policies.

This module configures himmelblau for the `register` join type, where a local
user is mapped to an Entra ID identity rather than using Entra ID as the
primary login. It includes patches for upstream bugs, compliance fixes for
MSIT conditional access on NixOS, and first-class WSL2 support.

## Usage

Add this flake as an input and import the module:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixtune.url = "github:yuzhoumo/nixtune";
    # Optional: pin nixpkgs for the himmelblau build
    nixtune.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nixtune, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixtune.nixosModules.default
        {
          modules.himmelblau = {
            localUser = "username";
            entraUser = "username@microsoft.com";
            wsl = true; # set to false for bare-metal / VM hosts
          };
        }
      ];
    };
  };
}
```

## Options

| Option                         | Type   | Default | Description                                                         |
|--------------------------------|--------|---------|---------------------------------------------------------------------|
| `modules.himmelblau.localUser` | string | N/A     | Local username to map to the Entra ID identity                      |
| `modules.himmelblau.entraUser` | string | N/A     | Entra ID UPN (email) to map the local user to                       |
| `modules.himmelblau.wsl`       | bool   | `false` | Enable WSL2-specific fixups (IPv6, FIDO passthrough, crypttab stub) |

## WSL2 Setup

For a complete guide to running nixtune on NixOS under WSL2 (including NixOS-WSL
installation, disk encryption with `wsl --manage`, and FIDO2 key passthrough via
usbipd) see **[docs/wsl-setup.md](docs/wsl-setup.md)**.

## After deploying

1. Rebuild: `sudo nixos-rebuild switch --flake .#myhost`
2. Enroll: `sudo aad-tool auth-test --name <entraUser>`
   - Set the Hello PIN to the **same password** as your local user.
   - Authenticate with your FIDO2 key when prompted.
3. Verify enrollment at https://portal.manage-beta.microsoft.com/devices

## Patches included

These fix upstream issues:

- **kanidm-hsm-crypto**: Strip empty `extensionRequest` attribute from CSRs that Microsoft's Intune API rejects.
- **libhimmelblau**: PEM-wrap CSRs for Intune enroll API; log response bodies on API errors; fallback manufacturer for WSL/no-DMI systems.
- **aad-tool**: Resolve local usernames via `user_map_file` in `auth-test`, so user-mapping mode works without a domain suffix.
- **himmelblau_policies**: Read `authority_host` / `tenant_id` / `graph_url` from config instead of passing `None`.
