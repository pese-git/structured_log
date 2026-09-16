/// Where a resolved configuration value came from — shown in
/// `--print-config` so an operator can tell an override from a default
/// (`log-server-config`).
enum ConfigSource { cli, env, file, defaultValue }
