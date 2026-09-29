# Site configure steps

Shell fragments (`NN-name.sh`) that run **after** every core step in
`core/configure/steps/`, inside the claw image, against the candidate config.
Use the helpers from `core/configure/lib.sh`: `set_json`, `set_str`,
`unset_key`, `has_key`, `json`, `openclaw`.

Typical site steps: agents and their sandboxes, roles, enabled skills and
plugins, hooks. A site step may override what a core step set — prefer that
over editing the core step.

Files not ending in `.sh` are ignored.
