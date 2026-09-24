# nix/package.nix
{ lib
, stdenvNoCC
, makeWrapper
, python3
, rsync
, callPackage
, quickshell
, gsettings-desktop-schemas
, src
, version ? "unstable"
, mascotSrc ? null                 # tarball from ./mascot-pack.nix (optional)
, extraRuntimePackages ? [ ]
}:

let
  deps = callPackage ./deps.nix { };
  runtime = deps.runtime ++ extraRuntimePackages;

  binPath = lib.makeBinPath runtime;
  qmlPath = lib.makeSearchPath "lib/qt-6/qml" deps.qml;
  pluginPath = lib.makeSearchPath "lib/qt-6/plugins" deps.qml;
  schemaDir = "${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}/glib-2.0/schemas";
  dataPath = lib.makeSearchPath "share" deps.dataPackages;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "inir";
  inherit version src;

  nativeBuildInputs = [ makeWrapper python3 rsync ];

  dontConfigure = true;
  dontBuild = true;

  # Keep `#!/usr/bin/env python3` intact: patchShebangs would pin it to a bare
  # interpreter without iNiR's modules. The wrapper PATH resolves python3 to the
  # closed environment instead. Non-executable files are skipped by fixupPhase.
  preFixup = ''
    find "$out/share/quickshell/inir" -type f -name '*.py' -exec chmod -x {} +
  '';
  postFixup = ''
    find "$out/share/quickshell/inir" -type f -name '*.py' -exec chmod +x {} +
  '';

  installPhase = ''
    runHook preInstall

    runtime="$out/share/quickshell/inir"
    mkdir -p "$runtime" "$out/bin" "$out/share/inir"

    # Upstream's own payload policy (excludes dev/CI/private files) if present.
    if [ -f sdata/lib/runtime-payload.py ]; then
      python3 sdata/lib/runtime-payload.py copy --root . --target "$runtime"
    else
      rsync -a --exclude .git --exclude nix ./ "$runtime/"
    fi

    chmod +x "$runtime/setup" "$runtime/scripts/inir" 2>/dev/null || true
    find "$runtime/scripts" -type f \( -name '*.sh' -o -name '*.fish' -o -name '*.py' \) -exec chmod +x {} \;

    # The source tree targets Arch where helpers live in /usr/bin (the launcher
    # even hardcodes /usr/bin/qs). Turn those into PATH lookups, keep shebangs.
    for d in modules services defaults scripts; do
      [ -d "$runtime/$d" ] || continue
      find "$runtime/$d" -type f \
        \( -name '*.qml' -o -name '*.js' -o -name '*.sh' -o -name '*.py' -o -name '*.fish' \) \
        -exec sed -i '1!s#/usr/bin/##g' {} +
    done

    python3 ${./patch-runtime.py} "$runtime"

    ${lib.optionalString (mascotSrc != null) ''
      # Kira art pack lives *inside* the runtime dir so the shell manifest finds it.
      mkdir -p "$runtime/assets/images/mascot"
      tar xf ${mascotSrc} -C "$runtime/assets/images/mascot/"
    ''}

    # Ship the dotfiles for the modules + a NixOS-ready niri config:
    #  * `qs -c inir ipc call X Y`  -> `inir X Y`   (no ~/.config/quickshell/inir needed)
    #  * drop the Arch polkit-mate agent spawn      (we run polkit-gnome as a user unit)
    #  * launch-terminal.sh from ~/.config          -> `inir terminal`
    #  * venv path                                  -> the closed Nix python env
    if [ -d dots/.config ]; then
      cp -r dots/.config "$out/share/inir/dots"
    fi
    if [ -f dots/.config/niri/config.kdl ]; then
      sed -e 's#"qs" "-c" "inir" "ipc" "call"#"inir"#g' \
          -e '/polkit-mate-authentication-agent-1/d' \
          -e 's#"bash" "-c" "$HOME/.config/quickshell/inir/scripts/launch-terminal.sh"#"inir" "terminal"#g' \
          -e 's#\$HOME/.local/state/quickshell/.venv#${deps.pythonEnv}#g' \
          dots/.config/niri/config.kdl > "$out/share/inir/niri-config.kdl"
    fi

    # Preserve the old default only for exact-content migration.
    cp "$out/share/inir/niri-config.kdl" "$out/share/inir/legacy-niri-config.kdl"
    rm -rf "$out/share/inir/dots/niri"
    cp -r defaults/niri "$out/share/inir/dots/niri"
    chmod -R u+w "$out/share/inir/dots"
    find "$out/share/inir/dots/niri" -name '*.kdl' -exec sed -i \
      -e '/polkit-mate-authentication-agent-1/d' \
      -e "s#~/.config/quickshell/inir#$runtime#g" \
      -e 's#\$HOME/.local/state/quickshell/.venv#${deps.pythonEnv}#g' {} +
    cp "$out/share/inir/dots/niri/config.kdl" "$out/share/inir/niri-config.kdl"
    ln -s dots/niri/config.d "$out/share/inir/config.d"
    # Settings/reset operations must see the same Nix-compatible defaults.
    cp -r --remove-destination "$out/share/inir/dots/niri/." "$runtime/defaults/niri/"
    cp -r --remove-destination "$out/share/inir/dots/niri/." "$runtime/dots/.config/niri/"
    cp ${./seed-config.py} "$out/share/inir/seed-config.py"
    makeWrapper ${deps.pythonEnv}/bin/python3 "$out/bin/inir-seed-config" \
      --add-flags "$out/share/inir/seed-config.py $out/share/inir/dots --legacy $out/share/inir/legacy-niri-config.kdl"

    makeWrapper "$runtime/scripts/inir" "$out/bin/inir" \
      --prefix PATH : "${binPath}" \
      --prefix QML2_IMPORT_PATH : "${qmlPath}" \
      --prefix QML_IMPORT_PATH : "${qmlPath}" \
      --prefix QT_PLUGIN_PATH : "${pluginPath}" \
      --prefix XDG_DATA_DIRS : "${dataPath}" \
      --set-default INIR_SYSTEM_RUNTIME_DIR "$runtime" \
      --set-default INIR_FALLBACK_SYSTEM_RUNTIME_DIR "$runtime" \
      --set-default GSETTINGS_SCHEMA_DIR "${schemaDir}" \
      --set-default INIR_VENV "${deps.pythonEnv}" \
      --set-default ILLOGICAL_IMPULSE_VIRTUAL_ENV "${deps.pythonEnv}" \
      --set-default QT_QPA_PLATFORMTHEME kde \
      --set-default XDG_MENU_PREFIX "plasma-" \
      --set-default XCURSOR_THEME "capitaine-cursors-light" \
      --set-default XCURSOR_SIZE 24 \
      --set-default QS_DISABLE_CRASH_HANDLER 1 \
      ${lib.optionalString deps.hasDarkly "--set-default QT_STYLE_OVERRIDE Darkly"}

    # Same environment for anyone who wants raw quickshell against this runtime.
    makeWrapper "${lib.getExe' quickshell "qs"}" "$out/bin/inir-qs" \
      --prefix PATH : "${binPath}" \
      --prefix QML2_IMPORT_PATH : "${qmlPath}" \
      --prefix QT_PLUGIN_PATH : "${pluginPath}" \
      --prefix XDG_DATA_DIRS : "${dataPath}" \
      --set-default GSETTINGS_SCHEMA_DIR "${schemaDir}" \
      --add-flags "-p $runtime"

    runHook postInstall
  '';

  passthru = {
    gsettingsSchemaDir = schemaDir;
    inherit (deps) pythonEnv fonts dataPackages hasDarkly;
    runtimeDependencies = runtime;
    sessionTools = deps.sessionTools ++ extraRuntimePackages;
    runtimeDir = "${placeholder "out"}/share/quickshell/inir";
    niriConfig = "${placeholder "out"}/share/inir/dots/niri/config.kdl";
    dots = "${placeholder "out"}/share/inir/dots";
  };

  meta = {
    description = "Complete desktop shell for Niri, built on Quickshell";
    homepage = "https://github.com/snowarch/iNiR";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "inir";
  };
})

