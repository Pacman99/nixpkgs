{ systemConfig, asConfig, lib, pkgs, ... }:

with lib;
let
  inherit (systemConfig.services.matrix-appservices)
    homeserverURL
    homeserverDomain;
  package = asConfig.package;
  pname = package.pname;
  command = "${package}/bin/${pname}";
  getDefaultConfig = file: builtins.fromJSON (builtins.readFile
    (pkgs.runCommand file { } ''
      file=$(find ${package.src} -name '${file}' | head -1)
      ${pkgs.yq}/bin/yq . $file > $out
    '')
  );

  mautrix = {
    # mautrix stores the registration tokens in the config file
    registerScript = ''
      ${command} --generate-registration \
        --config=$SETTINGS_FILE \
        --registration=$REGISTRATION_FILE
    '';

    startupScript = ''
      AS_TOKEN=$(cat $REGISTRATION_FILE | ${pkgs.yq}/bin/yq .as_token)
      HS_TOKEN=$(cat $REGISTRATION_FILE | ${pkgs.yq}/bin/yq .hs_token)
      mv $SETTINGS_FILE $SETTINGS_FILE.tmp
      cat $SETTINGS_FILE.tmp \
        | ${pkgs.jq}/bin/jq 'setpath(["appservice", "as_token"]; '$AS_TOKEN')' \
        | ${pkgs.jq}/bin/jq 'setpath(["appservice", "hs_token"]; '$HS_TOKEN')' \
        > $SETTINGS_FILE

      ${command} --config=$SETTINGS_FILE \
        --registration=$REGISTRATION_FILE
    '';

    settings =
      let
        defaultConfig = getDefaultConfig "example-config.yaml";
      in
      {
        homeserver = {
          address = homeserverURL;
          domain = homeserverDomain;
        };

        appservice = {
          inherit (defaultConfig.appservice)
            address
            hostname
            port
            id;

          state_store_path = "$DIR/mx-state.json";

          database = {
            type = "sqlite3";
            uri = "$DIR/database.db";
          };
        };

        bridge = {
          inherit (defaultConfig.bridge)
            username_template
            displayname_template
            command_prefix;

          permissions.${homeserverDomain} = "user";
        };
      };
  };

in
{
  other = {
    description = ''
      No defaults will be set.
    '';
  };

  matrix-appservice = {
    registerScript = ''
      url=$(cat $SETTINGS_FILE | ${pkgs.jq} .appserviceUrl)
      if [ -z $url ]; then
        url="http://localhost:$(cat $SETTINGS_FILE | ${pkgs.jq} .appservicePort)"
      fi
      ${command} --generate-registration \
        --config=$SETTINGS_FILE --url="$url" \
        --file=$REGISTRATION_FILE
    '';

    startupScript = ''
      port=$(cat $SETTINGS_FILE | ${pkgs.jq} .appservicePort)
      ${command} --config=$SETTINGS_FILE --url="$url" \
        --port=$port --file=$REGISTRATION_FILE
    '';

    description = ''
      For bridges based on the matrix-appservice-bridge library. The settings for these
      bridges are NOT configured automatically, because of the various differences
      between them. And you must set appservicePort(and optionally apserviceURL)
      in the settings to pass to the bridge - these settings are not usually part of the config file.
    '';
  };

  mx-puppet = {
    registerScript = ''
      ${command} \
        --register \
        --config=$SETTINGS_FILE \
        --registration-file=$REGISTRATION_FILE
    '';

    startupScript = ''
      ${command} \
        --config=$SETTINGS_FILE \
        --registration-file=$REGISTRATION_FILE
    '';

    settings =
      let
        defaultConfig = getDefaultConfig "sample.config.yaml";
      in
      {
        bridge = {
          inherit (defaultConfig.bridge) port;
          domain = homeserverDomain;
          homeserverUrl = homeserverURL;
        };
        database.filename = "$DIR/database.db";
        provisioning.whitelist = [ "@.*:${homeserverDomain}" ];
        relay.whitelist = [ "@.*:${homeserverDomain}" ];
      };

    serviceConfig.WorkingDirectory =
      "${package}/lib/node_modules/${pname}";

    description = ''
      For bridges based on the mx-puppet-bridge library. The settings will be
      configured to use a sqlite database. Make sure to override database.filename,
      if you plan to use another database.
    '';

  };

  mautrix-go = {
    inherit (mautrix) registerScript startupScript;
    settings =
      let
        defaultConfig = getDefaultConfig "example-config.yaml";
      in
      recursiveUpdate mautrix.settings
        { appservice.bot = defaultConfig.appservice.bot; };

    description = ''
      The settings are configured to use a sqlite database. The startupScript will
      create a new config file on every run to set the tokens, because mautrix
      requires them to be in the config file.
    '';
  };

  mautrix-python = {
    inherit (mautrix) registerScript;

    settings =
      let
        defaultConfig = getDefaultConfig "example-config.yaml";
      in
      recursiveUpdate mautrix.settings
        {
          appservice = {
            inherit (defaultConfig.appservice)
              bot_username
              bot_displayname
              bot_avatar;
          };
        };

    startupScript = optionalString (hasAttrByPath [ "alembic" ] package)
      "${package.alembic}/bin/alembic -x config=$SETTINGS_FILE upgrade head\n"
    + mautrix.startupScript;
    description = ''
      Same properties as mautrix-go. This will also upgrade the database on every run
    '';
  };

}
