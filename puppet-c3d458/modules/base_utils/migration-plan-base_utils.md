---
source-path: site/modules/common/base_utils
---

# Migration Plan: base_utils

**TLDR**: `base_utils` is a Linux host-baseline utility module invoked by `::profile::base::base` when `$manage_utils` is enabled. It manages `/etc/motd` and installs OS-family-specific utility packages. Debian-family hosts receive `vim`, `wget`, `curl`, `jq`, and `dnsutils`; RedHat-family hosts receive `vim-enhanced`, `wget`, `curl`, `jq`, and `bind-utils`; the default package list is empty. The module has no services, ports, PuppetDB dependencies, or credentials. Its Ansible equivalent should be a role with OS-family variables, an optional MOTD template, package tasks, and preservation of the supplied custom fact, functions, types, and Bolt-plan behavior where consumers require them.

## Service Type and Instances

**Service Type**: Linux host baseline / system utility configuration

**Configured Instances**:

- **MOTD management**
  - Location/Path: `/etc/motd`
  - Port/Socket: None
  - Source template: `base_utils/motd.erb`
  - Owner: `root`
  - Group: `root`
  - Mode: `0644`
  - Enabled by default: `true`
  - Render count: Once per applicable host

- **Debian-family package `vim`**
  - Package state: `installed`
  - Port/Socket: None

- **Debian-family package `wget`**
  - Package state: `installed`
  - Port/Socket: None

- **Debian-family package `curl`**
  - Package state: `installed`
  - Port/Socket: None

- **Debian-family package `jq`**
  - Package state: `installed`
  - Port/Socket: None

- **Debian-family package `dnsutils`**
  - Package state: `installed`
  - Port/Socket: None

- **RedHat-family package `vim-enhanced`**
  - Package state: `installed`
  - Port/Socket: None

- **RedHat-family package `wget`**
  - Package state: `installed`
  - Port/Socket: None

- **RedHat-family package `curl`**
  - Package state: `installed`
  - Port/Socket: None

- **RedHat-family package `jq`**
  - Package state: `installed`
  - Port/Socket: None

- **RedHat-family package `bind-utils`**
  - Package state: `installed`
  - Port/Socket: None

- **Generic/default package set**
  - Packages: None
  - Package loop iterations: 0
  - Port/Socket: None

## File Structure

```
site/role/manifests/app_stack.pp
site/profile/manifests/base/base.pp
site/profile/manifests/app/stack.pp
site/modules/common/base_utils/manifests/init.pp
site/modules/common/base_utils/data/common.yaml
site/modules/common/base_utils/data/os/Debian.yaml
site/modules/common/base_utils/data/os/RedHat.yaml
site/modules/common/base_utils/lib/facter/base_utils_info.rb
site/modules/common/base_utils/functions/ensure_value.pp
site/modules/common/base_utils/functions/normalize_port.pp
site/modules/common/base_utils/types/ensure_value.pp
site/modules/common/base_utils/types/log_level.pp
site/modules/common/base_utils/types/port.pp
site/modules/common/base_utils/plans/health_check.pp
site/modules/common/base_utils/plans/rolling_restart.pp
site/modules/linux/profile_app_stack/manifests/init.pp
site/modules/linux/profile_app_stack/manifests/python.pp
site/modules/linux/profile_app_stack/manifests/database.pp
site/modules/linux/profile_app_stack/manifests/app.pp
site/modules/linux/profile_app_stack/manifests/service.pp
site/modules/linux/profile_app_stack/manifests/monitoring.pp
base_utils/motd.erb
profile_app_stack/logrotate.conf.erb
profile_app_stack/app.env.erb
profile_app_stack/app.service.epp
```

The `profile_app_stack` manifests and templates are included for analysis completeness but are outside the `base_utils` execution subtree. Their migration status is to be handled by the separate application-stack migration.

## Module Explanation

The module-scoped execution path operates in this order:

1. **`role::app_stack`** (`site/role/manifests/app_stack.pp`):
   - Acts as the enclosing role entry point.
   - When `$facts['kernel'].downcase == 'linux'`, executes the role’s unspecified `exec` resource.
   - Includes `::profile::base::base`.
   - Includes `::profile::app::stack`.
   - Orders `Class['::profile::base::base']` before `Class['::profile::app::stack']`.
   - Migration disposition: preserve the ordering in the enclosing Ansible role or play; the unspecified `exec` requires separate implementation review.

2. **`::profile::base::base`** (`site/profile/manifests/base/base.pp`):
   - When `$manage_utils` is true, includes `base_utils`.
   - When `$manage_utils` is false, creates no `base_utils` resources.
   - When `$manage_ntp` is true and `$facts['kernel'] == 'Linux'`, installs package `chrony` and manages service `chronyd`.
   - When `$manage_syslog` is true and `$facts['kernel'] == 'Linux'`, installs package `rsyslog` and manages service `rsyslog`.
   - Uses `$facts['kernel']` for Linux gating.
   - Migration disposition: implement `$manage_utils` as an Ansible role variable such as `base_utils_manage_utils`; preserve the independent NTP and syslog conditionals in the parent base role.

3. **`base_utils`** (`site/modules/common/base_utils/manifests/init.pp`):
   - Resolves `base_utils::manage_motd` to `true`.
   - Resolves `base_utils::motd_template` to `base_utils/motd.erb`.
   - Resolves `base_utils::utility_packages` from common or OS-family Hiera data.
   - When `$manage_motd` is true, creates `/etc/motd` with owner `root`, group `root`, and mode `0644`.
   - Renders `base_utils/motd.erb` once per applicable host.
   - Passes no explicit variables to the template; the normal Puppet template scope is available.
   - Iterates over the Debian package list in this order:
     - `vim`
     - `wget`
     - `curl`
     - `jq`
     - `dnsutils`
   - Iterates over the RedHat package list in this order:
     - `vim-enhanced`
     - `wget`
     - `curl`
     - `jq`
     - `bind-utils`
   - Iterates zero times for the common/default empty package list.
   - Declares no `notify`, `subscribe`, `~>`, or `->` relationships.
   - Manages no service restart after package or MOTD changes.

### Out-of-scope analyzed manifests

The following manifests belong to the broader `profile_app_stack` execution tree rather than the `base_utils` subtree:

- **`::profile::app::stack`** (`site/profile/manifests/app/stack.pp`)
  - Out of scope for this module migration.
  - Migration disposition: migrate with the application-stack role.

- **`profile_app_stack`** (`site/modules/linux/profile_app_stack/manifests/init.pp`)
  - Out of scope for this module migration.
  - Migration disposition: migrate with the application-stack role.

- **`profile_app_stack::python`** (`site/modules/linux/profile_app_stack/manifests/python.pp`)
  - Out of scope for this module migration.
  - Migration disposition: migrate its Python resources with the application-stack role.

- **`profile_app_stack::database`** (`site/modules/linux/profile_app_stack/manifests/database.pp`)
  - Out of scope for this module migration.
  - Migration disposition: migrate its database resources with the application-stack role.

- **`profile_app_stack::app`** (`site/modules/linux/profile_app_stack/manifests/app.pp`)
  - Out of scope for this module migration.
  - Migration disposition: migrate its application files, packages, credentials, and service configuration with the application-stack role.

- **`profile_app_stack::service`** (`site/modules/linux/profile_app_stack/manifests/service.pp`)
  - Out of scope for this module migration.
  - Migration disposition: migrate its service resources with the application-stack role.

- **`profile_app_stack::monitoring`** (`site/modules/linux/profile_app_stack/manifests/monitoring.pp`)
  - Out of scope for this module migration.
  - Migration disposition: migrate its monitoring resources with the application-stack role.

The broader execution tree contains additional packages, users, groups, files, execs, services, cron jobs, virtual resources, and ordering relationships. Those resources are not part of the `base_utils` migration.

## Variables

**Variable Flow Summary**: 3 `base_utils` class parameters across common and OS-family Hiera levels, plus 1 external parent-profile inclusion variable.

### Variable Definitions

**`site/modules/common/base_utils/data/common.yaml` (defaults)** → Migration note: Base defaults for all nodes.

- `base_utils::manage_motd`: `true` (type: boolean)
  - Ansible mapping: `base_utils_manage_motd: true`
- `base_utils::motd_template`: `base_utils/motd.erb` (type: string)
  - Ansible mapping: `base_utils_motd_template: base_utils/motd.j2`
- `base_utils::utility_packages`: `[]` (type: array of strings)
  - Ansible mapping: `base_utils_utility_packages: []`

**`site/modules/common/base_utils/data/os/Debian.yaml` (Debian-family override)** → Migration note: OS-specific variables loaded for Debian-family systems.

- `base_utils::utility_packages`:
  - `vim`
  - `wget`
  - `curl`
  - `jq`
  - `dnsutils`
  - Type: array of strings
  - Ansible mapping:
    ```yaml
    base_utils_utility_packages:
      - vim
      - wget
      - curl
      - jq
      - dnsutils
    ```

**`site/modules/common/base_utils/data/os/RedHat.yaml` (RedHat-family override)** → Migration note: OS-specific variables loaded for RedHat-family systems.

- `base_utils::utility_packages`:
  - `vim-enhanced`
  - `wget`
  - `curl`
  - `jq`
  - `bind-utils`
  - Type: array of strings
  - Ansible mapping:
    ```yaml
    base_utils_utility_packages:
      - vim-enhanced
      - wget
      - curl
      - jq
      - bind-utils
    ```

**Parent-profile control variable** → Migration note: External inclusion control; the supplied effective default was not provided.

- `$manage_utils`: controls whether `base_utils` is included (type: boolean)
  - Ansible mapping: `base_utils_manage_utils`
  - Suggested value:
    ```yaml
    base_utils_manage_utils: true
    ```

The supplied plan identifies the Hiera values above, but the validation summary did not independently verify the Hiera source analysis. These values should be rechecked against the repository before implementation.

### Variable Migration Summary

- **Common defaults**: 3 variables from `common.yaml`
- **OS-specific variables**: 1 variable overridden independently for Debian and RedHat
- **Environment-specific variables**: 0 supplied
- **Host-specific variables**: 0 supplied
- **Encrypted variables**: 0 supplied for `base_utils`
- **Parent inclusion control**: 1 external variable, `$manage_utils`

### Cross-Level Overrides

- **`base_utils::utility_packages`**
  - Defined at `common.yaml`, `os/Debian.yaml`, and `os/RedHat.yaml`.
  - Merge strategy: `first`.
  - The matching OS-family value replaces the common empty array.
  - Package arrays are replaced as complete values; they are not hash- or deep-merged.

- **`base_utils::manage_motd`**
  - Defined only in `common.yaml`.
  - Effective value: `true`.

- **`base_utils::motd_template`**
  - Defined only in `common.yaml`.
  - Effective value: `base_utils/motd.erb`.

### Merge Strategy Notes

- Variables using `hash` merge combine hash values from multiple levels using a shallow merge.
- Variables using `deep` merge recursively merge nested values.
- Variables using `first`, the default strategy, use the first value found and do not merge arrays or hashes.
- `base_utils::utility_packages` uses replacement behavior under the first-found strategy.

## Custom Types and Providers

### Custom fact: `base_utils_info`

- File: `site/modules/common/base_utils/lib/facter/base_utils_info.rb`
- Scope: Linux only.
- Reports:
  - Whether `curl` is installed.
  - Whether `wget` is installed.
  - Whether `jq` is installed.
  - Whether `vim` is installed.
  - `uptime_seconds` from `/proc/uptime`, returned as an integer when available.
- Detects packages using `rpm` or `dpkg`.
- Ansible migration: implement under `facts.d` or as an Ansible fact plugin if consumers require it.
- The supplied `base_utils` execution tree does not show this fact being consumed.

### Function: `base_utils::ensure_value`

- File: `site/modules/common/base_utils/functions/ensure_value.pp`
- Input: optional string, default `undef`.
- Returns `default_value` when the input is `undef` or an empty string.
- Otherwise returns the input.
- Ansible migration: use `value | default(default_value, true)` unless exact Puppet type semantics require a custom filter.

### Function: `base_utils::normalize_port`

- File: `site/modules/common/base_utils/functions/normalize_port.pp`
- Input: string or integer.
- Converts the input using Puppet integer conversion.
- Invalid or non-integer values raise an error.
- Returns `Base_utils::Port`.
- Ansible migration: use a custom Jinja filter or assertion to convert and validate the value, including the range 1–65535.

### Type alias: `Base_utils::Ensure_value`

- File: `site/modules/common/base_utils/types/ensure_value.pp`
- Allowed values:
  - `present`
  - `absent`
  - `installed`
  - `latest`
  - `purged`
- Ansible migration: use native module state values and `ansible.builtin.assert` where shared variables require enum validation.

### Type alias: `Base_utils::Log_level`

- File: `site/modules/common/base_utils/types/log_level.pp`
- Allowed values:
  - `debug`
  - `info`
  - `notice`
  - `warning`
  - `error`
  - `critical`
  - `alert`
  - `emergency`
- Ansible migration: use role argument validation or `ansible.builtin.assert`.

### Type alias: `Base_utils::Port`

- File: `site/modules/common/base_utils/types/port.pp`
- Allowed values: integer from `1` through `65535`.
- Ansible migration: use native integer validation or an assertion.

### Bolt plan: `base_utils::health_check`

- File: `site/modules/common/base_utils/plans/health_check.pp`
- Parameters:
  - `targets`: `TargetSpec`
  - `service`: string, default `sshd`
- Runs `base_utils::check_service` across targets.
- Filters results whose status is not `running`.
- Emits healthy or unhealthy status.
- Returns task results.
- Ansible migration: use `service_facts` or service-status checks; no custom module is required unless `check_service` provides unavailable behavior.

### Bolt plan: `base_utils::rolling_restart`

- File: `site/modules/common/base_utils/plans/rolling_restart.pp`
- Parameters:
  - `targets`: `TargetSpec`
  - `service`: string
  - `delay_seconds`: integer, default `30`
- Resolves targets.
- Runs `systemctl restart` sequentially.
- Verifies that the service is running.
- Fails on an unsuccessful restart.
- Sleeps between targets.
- Ansible migration: use `serial: 1`, `ansible.builtin.systemd_service`, service-state validation, `failed_when`, and `ansible.builtin.pause` with `seconds: 30`.

The custom-component descriptions above are independently supplied migration information and were not verifiable from the validation summary alone.

## Dependencies

**External module dependencies**:

- `puppetlabs-stdlib` `9.7.0`
- `puppetlabs-concat` `9.0.2`
- `puppetlabs-firewall` `8.1.3`
- `puppetlabs-vcsrepo` `6.1.0`
- `puppet-redis` `11.0.0`
- `puppetlabs-apt` `9.4.0`

The `base_utils` manifest does not directly declare resources from these modules.

**System package dependencies**:

- Debian-family:
  - `vim`
  - `wget`
  - `curl`
  - `jq`
  - `dnsutils`
- RedHat-family:
  - `vim-enhanced`
  - `wget`
  - `curl`
  - `jq`
  - `bind-utils`

**Service dependencies**:

- None within `base_utils`.
- The parent base profile separately manages `chronyd` when `$manage_ntp` is true on Linux.
- The parent base profile separately manages `rsyslog` when `$manage_syslog` is true on Linux.
- The enclosing role orders `Class['::profile::base::base']` before `Class['::profile::app::stack']`.

## Puppet Facts Used

- `$facts['kernel']`
  - Identifies the operating system kernel.
  - Used by `site/role/manifests/app_stack.pp` and `site/profile/manifests/base/base.pp` for Linux-only behavior.
  - Directly referenced by the surrounding execution path, not by the `base_utils` manifest itself.

- `fact('environment')` / `$facts['environment']`
  - Identifies the Puppet environment.
  - Used by the application monitoring profile.
  - Not used by `base_utils`.

- `base_utils_info`
  - Reports Linux package presence and uptime.
  - Not shown as consumed by the supplied `base_utils` execution tree.

## Template Conversion Notes

### `base_utils/motd.erb`

- Source: `base_utils/motd.erb`
- Destination: `/etc/motd`
- Render count: once per applicable host when `$manage_utils` and `base_utils::manage_motd` are both true.
- Owner: `root`
- Group: `root`
- Mode: `0644`
- Explicit manifest variables: none.
- Scope: normal Puppet template scope and facts may be available.
- Ruby logic and exact variable references were not supplied.
- Migration action: inspect the template before creating the equivalent `base_utils/motd.j2`.

### Out-of-scope application-stack templates

- **`profile_app_stack/logrotate.conf.erb`**
  - Associated with the application-stack migration.
  - Destination, render count, variables, and exact logic were not supplied in the validated `base_utils` data.
  - Migration action: document and convert with the application-stack role.

- **`profile_app_stack/app.env.erb`**
  - Associated with the application-stack migration.
  - Destination, render count, variables, and exact logic were not supplied.
  - Credential handling must be reviewed before conversion; no conclusion about application-stack secrets can be made from the `base_utils` analysis.

- **`profile_app_stack/app.service.epp`**
  - Associated with the application-stack migration.
  - Requires EPP-to-Jinja conversion and systemd unit validation.
  - Destination, render count, variables, and exact conditional logic were not supplied.

## Credentials

- No credentials are defined or consumed by the `base_utils` manifest.
- No eyaml-encrypted values were supplied for `base_utils`.
- No `Sensitive` values are used by the `base_utils` manifest.
- The broader application-stack execution tree includes `profile_app_stack/app.env.erb`, but its contents and any credential usage were not supplied.
- Do not claim that the complete analyzed execution tree is credential-free until `profile_app_stack/app.env.erb` and its Hiera inputs have been inspected.

## Checks for the Migration

**Files to verify**:

- `site/role/manifests/app_stack.pp`
- `site/profile/manifests/base/base.pp`
- `site/profile/manifests/app/stack.pp`
- `site/modules/common/base_utils/manifests/init.pp`
- `site/modules/common/base_utils/data/common.yaml`
- `site/modules/common/base_utils/data/os/Debian.yaml`
- `site/modules/common/base_utils/data/os/RedHat.yaml`
- `site/modules/common/base_utils/lib/facter/base_utils_info.rb`
- `site/modules/common/base_utils/functions/ensure_value.pp`
- `site/modules/common/base_utils/functions/normalize_port.pp`
- `site/modules/common/base_utils/types/ensure_value.pp`
- `site/modules/common/base_utils/types/log_level.pp`
- `site/modules/common/base_utils/types/port.pp`
- `site/modules/common/base_utils/plans/health_check.pp`
- `site/modules/common/base_utils/plans/rolling_restart.pp`
- `base_utils/motd.erb`
- `profile_app_stack/logrotate.conf.erb`
- `profile_app_stack/app.env.erb`
- `profile_app_stack/app.service.epp`
- `site/modules/linux/profile_app_stack/manifests/init.pp`
- `site/modules/linux/profile_app_stack/manifests/python.pp`
- `site/modules/linux/profile_app_stack/manifests/database.pp`
- `site/modules/linux/profile_app_stack/manifests/app.pp`
- `site/modules/linux/profile_app_stack/manifests/service.pp`
- `site/modules/linux/profile_app_stack/manifests/monitoring.pp`

**Service endpoints to check**:

- None. `base_utils` does not listen on a port or manage a service.

**Templates rendered**:

- `base_utils/motd.erb` → `/etc/motd`
  - Render count: once per applicable host.
- `profile_app_stack/logrotate.conf.erb`
  - Render count and destination: verify in the application-stack migration.
- `profile_app_stack/app.env.erb`
  - Render count and destination: verify in the application-stack migration.
- `profile_app_stack/app.service.epp`
  - Render count and destination: verify in the application-stack migration.

## Pre-flight checks

```bash
# Confirm the host is Linux
test "$(uname -s)" = "Linux"

# Confirm the parent inclusion gate is enabled
# Verify base_utils_manage_utils=true in the selected Ansible inventory or group_vars.

# Verify the Debian-family package names individually
apt-cache show vim
apt-cache show wget
apt-cache show curl
apt-cache show jq
apt-cache show dnsutils

# Verify the RedHat-family package names individually
dnf info vim-enhanced
dnf info wget
dnf info curl
dnf info jq
dnf info bind-utils

# Verify the MOTD file
stat -c '%U:%G %a %n' /etc/motd
test "$(stat -c '%U:%G' /etc/motd)" = "root:root"
test "$(stat -c '%a' /etc/motd)" = "644"

# Verify the Debian-family package instances individually
dpkg-query -W vim
dpkg-query -W wget
dpkg-query -W curl
dpkg-query -W jq
dpkg-query -W dnsutils

# Verify the RedHat-family package instances individually
rpm -q vim-enhanced
rpm -q wget
rpm -q curl
rpm -q jq
rpm -q bind-utils

# Verify the default package set behavior
# Confirm no package task is executed when base_utils_utility_packages is an empty list.

# Validate the custom fact output, if migrated
facter base_utils_info
# Check curl, wget, jq, vim, and uptime_seconds individually.

# Validate the MOTD content
diff -u /etc/motd <(ansible localhost -m template \
  -a "src=base_utils/motd.j2 dest=/tmp/base_utils.motd" \
  --check 2>/dev/null)

# Confirm no base_utils service endpoint exists
ss -ltn
ss -lx
```