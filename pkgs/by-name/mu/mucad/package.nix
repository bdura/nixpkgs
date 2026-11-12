{
  lib,
  stdenv,
  fetchFromCodeberg,
  rustPlatform,
  pkg-config,
  wayland,
  installShellFiles,
  versionCheckHook,
  nix-update-script,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "mucad";
  version = "0.6.2";
  __structuredAttrs = true;

  src = fetchFromCodeberg {
    owner = "mucad";
    repo = "mucad";
    tag = "v${finalAttrs.version}";
    hash = "sha256-KRlhhFcgDpdiZR5cc/VDgdFNejq1CnOkQD1P8N3brFY=";
  };

  cargoHash = "sha256-7cQRboJ0XLErGnTAnT9GFR7d5nP2/yn+dQlyttQb6+I=";

  nativeBuildInputs = [
    installShellFiles
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ pkg-config ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ wayland ];

  cargoBuildFlags = [
    "-p"
    "mucad"
    "-p"
    "mucad-viewer"
    "-p"
    "mucad-lsp"
  ];
  cargoTestFlags = finalAttrs.cargoBuildFlags;

  # The CLI tests install the std library into the user config directory.
  preCheck = ''
    export HOME=$(mktemp -d)
  '';

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd mucad \
      --bash <($out/bin/mucad completions bash) \
      --zsh <($out/bin/mucad completions zsh) \
      --fish <($out/bin/mucad completions fish)
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "CAD programming language for everybody";
    homepage = "https://mucad.org";
    changelog = "https://codeberg.org/mucad/mucad/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Plus;
    mainProgram = "mucad";
    donationPage = "https://opencollective.com/mucad/donate";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    maintainers = with lib.maintainers; [ bdura ];
  };
})
