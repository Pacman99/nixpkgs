{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.services.matrix-appservices;
  asOpts = import ./as-options.nix {
    inherit lib pkgs;
    systemConfig = config;
  };
  mkService = name: opts:
    with opts;
    let
      settingsFormat = pkgs.formats.json { };
      dataDir = "/var/lib/matrix-as-${name}";
      registrationFile = "${dataDir}/${name}-registration.yaml";
      # Replace all references to $DIR to the dat directory
      settingsData = settingsFormat.generate "config.json"
        (mapAttrsRecursive
          (_: v:
            if builtins.isString v then
              (builtins.replaceStrings [ "$DIR" ] [ dataDir ] v) else v)
          settings);
      settingsFile = "${dataDir}/config.json";
      setVars = ''
        SETTINGS_FILE=${settingsFile}
        REGISTRATION_FILE=${registrationFile}
      '';
      serviceDeps = [ "network-online.target" ] ++ serviceDependencies
        ++ (optionals (cfg.homeserver != null) [ "${cfg.homeserver}.service" ]);
    in
    {
      description = "A matrix appservice for ${name}.";

      wantedBy = [ "multi-user.target" ];
      wants = serviceDeps;
      after = serviceDeps;

      preStart = ''
        cp ${settingsData} ${settingsFile}
        chmod 640 ${settingsFile}

        if [ ! -f '${registrationFile}' ]; then
          ${setVars}
          ${registerScript}
          chmod 640 ${registrationFile}
        fi
      '';

      script = ''
        ${setVars}
        ${startupScript}
      '';

      serviceConfig = {
        Type = "simple";
        Restart = "always";

        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;

        User = "matrix-appservice";
        Group = cfg.homeserver;
        PrivateTmp = true;
        WorkingDirectory = dataDir;
        StateDirectory = "${baseNameOf dataDir}";
        UMask = 0027;
      } // opts.serviceConfig;
    };

in
{
  options = {
    services.matrix-appservices = {
      services = mkOption {
        type = types.attrsOf asOpts;
        example = ''
          whatsapp = {
            format = "mautrix";
            package = pkgs.whatsapp;
          };
        '';
        description = ''
          Appservices to setup.
          Each appservice will be started as a systemd service with the prefix matrix-as.
          And its data will be stored in /var/lib/matrix-as-name.
        '';
      };

      homeserver = mkOption {
        type = types.enum [ "matrix-synapse" null ];
        default = "matrix-synapse";
        description = ''
          The homeserver software the appservices connect to. This will ensure appservices
          start after the homeserver and it will be used by the addRegistrationFiles option.
        '';
      };

      homeserverURL = mkOption {
        type = types.str;
        default = "https://${cfg.homeserverDomain}";
        description = ''
          URL of the homeserver the apservices connect to
        '';
      };

      homeserverDomain = mkOption {
        type = types.str;
        default = if config.networking.domain != null then config.networking.domain else "";
        defaultText = "\${config.networking.domain}";
        description = ''
          Domain of the homeserver the appservices connect to
        '';
      };

      addRegistrationFiles = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to add the application service registration files to the homeserver configuration.
          This should only be done after all application services have registered and the registration
          files have been verified - they can be found in /var/lib/matrix-as-*.
          Most homeservers will not start if any of the registration files are not found. So adding new
          bridges usually takes multiple configuration switches.
        '';
      };
    };
  };

  config = mkIf (cfg.services != { }) {

    assertions = mapAttrsToList
      (n: v: {
        assertion = v.format != "other" && v.package != null;
        message = "A package must be provided if a custom format is set";
      })
      cfg.services;

    users.users.matrix-appservice = { };

    systemd.services = mapAttrs' (n: v: nameValuePair "matrix-as-${n}" (mkService n v)) cfg.services;

    services = mkIf cfg.addRegistrationFiles {
      matrix-synapse.app_service_config_files = mkIf (cfg.homeserver == "matrix-synapse")
        (mapAttrsToList (n: _: "/var/lib/matrix-as-${n}/${n}-registration.yaml") cfg.services);
    };
  };

  meta.maintainers = with maintainers; [ pacman99 ];

}
