{ config, lib, pkgs, himmelblau, ... }:

# Applies bug-fix patches to three crates that are not yet fixed upstream:
#
# kanidm-hsm-crypto:
#   x509-cert 0.2's RequestBuilder adds an empty extensionRequest that
#   Microsoft's Intune API rejects. The patch strips it and manually
#   assembles the CertificateRequest with correct DER encoding.
#
# libhimmelblau:
#   - CSR must be PEM-wrapped (not raw base64) for the Intune enroll API.
#   - Intune API errors only include the status code; patch adds the
#     response body for diagnostics.
#   - get_manufacturer() returns "" on systems without DMI (e.g. WSL).
#     The Intune details() API requires a non-empty Manufacturer field.
#
# himmelblau_policies:
#   apply_intune_policy passes None for authority_host / tenant_id / graph_url
#   when constructing the Graph client, causing "federation provider not set"
#   errors. The patch reads them from the config.
#
# aad-tool:
#   auth-test --name calls map_name_to_upn() which short-circuits for local
#   users (in /etc/passwd), never consulting the user_map_file. The patch
#   checks the user map first, matching what the PAM module does.

let
  system = pkgs.stdenv.hostPlatform.system;

  patchedPkgs = pkgs.extend (final: prev: {
    defaultCrateOverrides = prev.defaultCrateOverrides // {
      "kanidm-hsm-crypto" = attrs: {
        postPatch = ''
          patch -p1 < ${./patches/kanidm-hsm-csr-strip-extensions.patch}
        '';
      };
      "libhimmelblau" = attrs: {
        postPatch = ''
          patch -p1 < ${./patches/libhimmelblau-intune-pem-wrap.patch}
          patch -p1 < ${./patches/libhimmelblau-manufacturer-fallback.patch}
          # Log response body on Intune API errors (identical pattern in 4 places)
          sed -i 's|Err(MsalError::GeneralFailure(format!("{}", resp.status())))|{ let _st = resp.status(); let _bd = resp.text().await.unwrap_or_default(); tracing::error!("Intune API error: {} - {}", _st, _bd); Err(MsalError::GeneralFailure(format!("{}: {}", _st, _bd))) }|g' src/intune.rs
        '';
      };
      "himmelblau_policies" = attrs: {
        postPatch = ''
          patch -p1 < ${./patches/himmelblau-policies-federation-provider.patch}
        '';
      };
    };
  });

  # Patch the himmelblau source tree before importing it, so the
  # aad-tool fix is baked into the source that crate2nix builds.
  # This avoids fighting with the upstream default.nix's own
  # defaultCrateOverrides // { aad-tool = ...; } which clobbers
  # any overlay we set for crates it also overrides.
  patchedHimmelblauSrc = pkgs.runCommand "himmelblau-patched-src" {} ''
    cp -r ${himmelblau} $out
    chmod -R u+w $out
    cd $out/src/cli
    patch -p1 < ${./patches/aad-tool-auth-test-user-map.patch}
  '';

  patchedHimmelblau = import patchedHimmelblauSrc {
    inherit system;
    pkgs = patchedPkgs;
  };
in
{
  services.himmelblau = {
    daemonPackage = lib.mkForce patchedHimmelblau.packages.daemon;
    pamPackage = lib.mkForce patchedHimmelblau.packages.pam;
    nssPackage = lib.mkForce patchedHimmelblau.packages.nss;
    ssoPackage = lib.mkForce patchedHimmelblau.packages.sso;
    brokerPackage = lib.mkForce patchedHimmelblau.packages.broker;
  };

  environment.systemPackages = [
    patchedHimmelblau.packages.aad-tool
  ];
}
