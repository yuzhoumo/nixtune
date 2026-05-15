{
  description = "NixOS module for Entra ID / Intune enrollment using himmelblau in user-mapping mode";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    himmelblau = {
      url = "github:himmelblau-idm/himmelblau/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, himmelblau, ... }: {
    nixosModules = rec {
      default = himmelblau-entra;
      himmelblau-entra = {
        imports = [ ./module ];
        _module.args.himmelblau = himmelblau;
      };
    };
  };
}
