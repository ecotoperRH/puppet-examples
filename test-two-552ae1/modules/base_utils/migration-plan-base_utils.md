---
source-path: site/modules/common/base_utils
---

# Migration Plan: base_utils

**TLDR**: `base_utils` is a lightweight "common baseline" Puppet module that runs on every Linux node as part of `profile::base::base`. It does two things: (1) optionally renders an `/etc/motd` banner from a template, and (2) installs a small set of OS-appropriate utility packages (`vim`/`vim-enhanced`, `wget`, `curl`, `jq`, `dnsutils`/`bind-utils`). The module also ships custom Puppet type aliases, helper functions, a custom Facter fact, and two Bolt Plans — none of which have direct Ansible resource equivalents but all map cleanly to native Ansible constructs. The module is invoked conditionally by `profile::base::base` when `$manage_utils` is `true` (the default). The defined types `config_entry.pp`, `create_dir.pp`, and `managed_notify.pp` are present in the module but are not instantiated anywhere in the `base_utils` execution tree — they are dead code relative to this module's role and produce no resources to migrate.

---

## Service Type and Instances

**Service Type**: Baseline OS utility configuration (not a long-running service)

**Configured Instances**:
- **motd**: Message-of-the-day banner at `/etc/motd`
  - Template: `base_utils/motd.erb`
  - Rendered once per node
  - Controlled by: `base_utils::manage_motd: true` (default)
- **utility-packages-debian**: Package set for Debian/Ubuntu hosts
  - Packages: `vim`, `wget`, `curl`, `jq`, `dnsutils`
  - Source: `site/modules/common/base_utils/data/os/Debian.yaml`
- **utility-packages-redhat**: Package set for RedHat/CentOS/Rocky hosts
  - Packages: `vim-enhanced`, `wget`, `curl`, `jq`, `bind-utils`
  - Source: `site/modules/common/base_utils/data/os/RedHat.yaml`

---

## File Structure

```
site/
├── modules/
│   └── common/
│       └── base_utils/
│           ├── manifests/
│           │   ├── init.pp                  # main class entry point
│           │   ├── config_entry.pp          # defined type (not instantiated — dead code)
│           │   ├── create_dir.pp            # defined type (not instantiated — dead code)
│           │   └── managed_notify.pp        # defined type (not instantiated — dead code)
│           ├── templates/
│           │   └── motd.erb                 # rendered to /etc/motd
│           ├── functions/
│           │   ├── ensure_value.pp          # null-coalescing helper function
│           │   └── normalize_port.pp        # port coercion helper function
│           ├── types/
│           │   ├── ensure_value.pp          # type alias Base_utils::Ensure_value
│           │   ├── log_level.pp             # type alias Base_utils::Log_level
│           │   └── port.pp                  # type alias Base_utils::Port
│           ├── plans/
│           │   ├── health_check.pp          # Bolt Plan for service health checking
│           │   └── rolling_restart.pp       # Bolt Plan for rolling service restarts
│           ├── lib/
│           │   └── facter/
│           │       └── base_utils_info.rb   # custom Facter fact base_utils_info
│           ├── data/
│           │   ├── common.yaml              # module-level defaults
│           │   └── os/
│           │       ├── Debian.yaml          # Debian/Ubuntu package list override
│           │       └── RedHat.yaml          # RHEL/CentOS/Rocky package list override
│           └── hiera.yaml                   # module Hiera hierarchy definition
└── profile/
    └── manifests/
        └── base/
            └── base.pp                      # caller profile that conditionally includes base_utils
```

---

## Module Explanation

The module performs operations in this order:

### Execution Entry: `profile::base::base` (`site/profile/manifests/base/base.pp`)

Class parameters resolved from Hiera (all from `data/common.yaml` root-level, no module-level overrides):
- `$manage_utils` → `true` (default; no Hiera override found)
- `$manage_ntp` → `true` (default)
- `$manage_syslog` → `true` (default)

**Conditional: `if $manage_utils` → `true` (always executes)**
- `include base_utils` → walks into `base_utils` class below

**Conditional: `if $manage_ntp and $facts['kernel'] == 'Linux'` → `true` on Linux**
- `package 'chrony'` → ensure: `installed`
- `service 'chronyd'` → ensure: `running`, enable: `true`

**Conditional: `if $manage_syslog and $facts['kernel'] == 'Linux'` → `true` on Linux**
- `package 'rsyslog'` → ensure: `installed`
- `service 'rsyslog'` → ensure: `running`, enable: `true`

---

### 1. `base_utils` (`site/modules/common/base_utils/manifests/init.pp`)

Class parameters resolved from Hiera (module hierarchy: `os/Debian.yaml` or `os/RedHat.yaml` → `common.yaml`):
- `$manage_motd` → `true` (from `common.yaml`: `base_utils::manage_motd: true`)
- `$motd_template` → `'base_utils/motd.erb'` (from `common.yaml`: `base_utils::motd_template: 'base_utils/motd.erb'`)
- `$utility_packages` → OS-dependent (see loop expansion below; `common.yaml` default `[]` is fully replaced by OS-level file)

**Conditional: `if $manage_motd` → `true` (always executes)**
- `file '/etc/motd'` (template `base_utils/motd.erb`) → ensure: `file`, owner: `root`, group: `root`, mode: `0644`
  - Template variables:
    - `@facts['networking']['fqdn']` → node's fully-qualified domain name (e.g., `lb01.fra.example.com`)
    - `@facts['os']['name']` → OS name (e.g., `Ubuntu`, `CentOS`)
    - `@facts['os']['release']['full']` → full OS release string (e.g., `22.04`, `8.6`)
    - `@facts['kernelrelease']` → kernel version string (e.g., `5.15.0-91-generic`)
    - `@facts['system_uptime']['uptime']` → human-readable uptime string (e.g., `3 days`)
  - Rendered content example:
    ```
    ========================================
      Managed by Puppet
      Hostname: lb01.fra.example.com
      OS:       Ubuntu 22.04
      Kernel:   5.15.0-91-generic
      Uptime:   3 days
    ========================================
    ```

**Loop: `$utility_packages.each |$pkg|`**

- **On Debian/Ubuntu hosts** (`os/Debian.yaml` fully replaces `common.yaml` default `[]`):
  - Loop runs **5 times** for: `vim`, `wget`, `curl`, `jq`, `dnsutils`
    - `package 'vim'` → ensure: `installed`
    - `package 'wget'` → ensure: `installed`
    - `package 'curl'` → ensure: `installed`
    - `package 'jq'` → ensure: `installed`
    - `package 'dnsutils'` → ensure: `installed`

- **On RedHat/CentOS/Rocky hosts** (`os/RedHat.yaml` fully replaces `common.yaml` default `[]`):
  - Loop runs **5 times** for: `vim-enhanced`, `wget`, `curl`, `jq`, `bind-utils`
    - `package 'vim-enhanced'` → ensure: `installed`
    - `package 'wget'` → ensure: `installed`
    - `package 'curl'` → ensure: `installed`
    - `package 'jq'` → ensure: `installed`
    - `package 'bind-utils'` → ensure: `installed`

- **On hosts with no OS-level override** (e.g., unknown OS family):
  - Loop runs **0 times** — `$utility_packages` resolves to `[]` from `common.yaml`
  - No packages are installed

**Defined types present but not instantiated (dead code — no resources to migrate)**:
- `base_utils::config_entry` (`site/modules/common/base_utils/manifests/config_entry.pp`) — not called anywhere in the execution tree
- `base_utils::create_dir` (`site/modules/common/base_utils/manifests/create_dir.pp`) — not called anywhere in the execution tree
- `base_utils::managed_notify` (`site/modules/common/base_utils/manifests/managed_notify.pp`) — not called anywhere in the execution tree

---

## Variables

**Variable Flow Summary**: 3 variables across 3 Hiera levels (1 module common + 2 OS-family overrides)

### Variable Definitions

**`site/modules/common/base_utils/data/common.yaml` (module defaults — lowest priority)** → Migration note: Base defaults applied to all nodes; these values are used unless overridden by an OS-family file
- `base_utils::manage_motd`: `true` (type: boolean) — controls whether `/etc/motd` is managed
- `base_utils::motd_template`: `'base_utils/motd.erb'` (type: string) — Puppet template path for MOTD content
- `base_utils::utility_packages`: `[]` (type: array of strings) — empty default; fully replaced by OS-level files

**`site/modules/common/base_utils/data/os/Debian.yaml` (OS family level — overrides common for Debian/Ubuntu)** → Migration note: OS-specific variables, loaded conditionally when `ansible_os_family == 'Debian'`
- `base_utils::utility_packages`: `['vim', 'wget', 'curl', 'jq', 'dnsutils']` (type: array of strings)

**`site/modules/common/base_utils/data/os/RedHat.yaml` (OS family level — overrides common for RHEL/CentOS/Rocky)** → Migration note: OS-specific variables, loaded conditionally when `ansible_os_family == 'RedHat'`
- `base_utils::utility_packages`: `['vim-enhanced', 'wget', 'curl', 'jq', 'bind-utils']` (type: array of strings)

### Variable Migration Summary

- **Common defaults**: 3 variables (`manage_motd`, `motd_template`, `utility_packages`) from `common.yaml` — base configuration for all nodes
- **OS-specific variables**: 1 variable overridden at OS level (`utility_packages`) — 2 OS variants (Debian, RedHat)
- **Environment-specific variables**: 0 variables
- **Host-specific variables**: 0 variables
- **Encrypted variables**: 0 variables — no eyaml in this module

### Cross-Level Overrides

- **`base_utils::utility_packages`**: defined at `common.yaml` (default `[]`) and overridden at `os/Debian.yaml` and `os/RedHat.yaml`; merge strategy: `first` (priority lookup — OS value fully replaces common default, no array merging)

### Merge Strategy Notes

- Variables using `first` (default) — First value found wins, no merging. `base_utils::utility_packages` uses this strategy: the OS-family file value completely replaces the `common.yaml` empty array default.

---

## Custom Types and Providers

### Custom Fact: `base_utils_info`
- **File**: `site/modules/common/base_utils/lib/facter/base_utils_info.rb`
- **Scope**: Linux-only (confined to `kernel: 'Linux'`)
- **Returns**: A hash with:
  - `curl` (Boolean) — whether `curl` package is installed (checked via `rpm -q` or `dpkg -l`)
  - `wget` (Boolean) — whether `wget` package is installed
  - `jq` (Boolean) — whether `jq` package is installed
  - `vim` (Boolean) — whether `vim` package is installed
  - `uptime_seconds` (Integer) — system uptime read from `/proc/uptime`
- **Ansible equivalent**: Use `ansible.builtin.package_facts` to populate `ansible_facts.packages` for package presence checks. Use `ansible_uptime_seconds` from `ansible.builtin.setup` for uptime. For a direct 1:1 migration, deploy a custom fact script to `/etc/ansible/facts.d/base_utils_info.fact`.

### Helper Function: `base_utils::ensure_value`
- **File**: `site/modules/common/base_utils/functions/ensure_value.pp`
- **Behaviour**: Null-coalescing guard — returns `$input` if it is a non-empty string, otherwise returns `$default_value`
- **Parameters**:
  - `input` (Optional[String]) — value to check; may be `undef` or empty string
  - `default_value` (String) — fallback value
- **Ansible equivalent**: Jinja2 `default` filter: `{{ my_var | default('fallback', true) }}` (the `true` second argument treats empty strings as falsy, matching Puppet behaviour)

### Helper Function: `base_utils::normalize_port`
- **File**: `site/modules/common/base_utils/functions/normalize_port.pp`
- **Behaviour**: Coerces a String or Integer port value to a validated Integer constrained by `Base_utils::Port` (1–65535)
- **Parameters**:
  - `port` (Variant[String, Integer]) — port value to normalize
- **Ansible equivalent**: Jinja2 `| int` filter for coercion; range validation via `assert` task or `argument_spec` with `type: int` plus range check. No custom Ansible module needed.

### Type Alias: `Base_utils::Ensure_value`
- **File**: `site/modules/common/base_utils/types/ensure_value.pp`
- **Constrains**: `Enum['present', 'absent', 'installed', 'latest', 'purged']`
- **Ansible equivalent**: `choices: [present, absent, installed, latest, purged]` in `argument_spec`, or native package/service module state parameters. No custom module needed.

### Type Alias: `Base_utils::Log_level`
- **File**: `site/modules/common/base_utils/types/log_level.pp`
- **Constrains**: `Enum['debug', 'info', 'notice', 'warning', 'error', 'critical', 'alert', 'emergency']`
- **Ansible equivalent**: `choices: ['debug','info','notice','warning','error','critical','alert','emergency']` in `argument_spec` or role variable validation. No custom module needed.

### Type Alias: `Base_utils::Port`
- **File**: `site/modules/common/base_utils/types/port.pp`
- **Constrains**: `Integer[1, 65535]`
- **Ansible equivalent**: `argument_spec` with `type: int` and range check, or an `assert` task: `assert: that: - my_port >= 1 - my_port <= 65535`. No custom module needed.

### Bolt Plan: `base_utils::health_check`
- **File**: `site/modules/common/base_utils/plans/health_check.pp`
- **Behaviour**: Runs `base_utils::check_service` Bolt task on all targets; filters for non-running services; prints summary; returns results
- **Parameters**:
  - `targets` (TargetSpec) — nodes to check
  - `service` (String, default: `'sshd'`) — service name to check
- **Ansible equivalent**: Playbook using `ansible.builtin.service_facts` + `ansible.builtin.debug` or `ansible.builtin.fail` with a `when` condition filtering hosts where `ansible_facts.services[service_name].state != 'running'`

### Bolt Plan: `base_utils::rolling_restart`
- **File**: `site/modules/common/base_utils/plans/rolling_restart.pp`
- **Behaviour**: Sequentially restarts a named systemd service on each target; verifies running state post-restart via `base_utils::check_service`; fails early if not running; sleeps `delay_seconds` between hosts
- **Parameters**:
  - `targets` (TargetSpec) — nodes to restart on
  - `service` (String) — systemd service name
  - `delay_seconds` (Integer, default: `30`) — inter-host pause in seconds
- **Ansible equivalent**: Playbook with `serial: 1`, `ansible.builtin.service` (state: restarted), `ansible.builtin.service_facts` or `ansible.builtin.wait_for` for health check, and `ansible.builtin.pause` (seconds: 30) between hosts

---

## Dependencies

**External module dependencies** (from `metadata.json` / Puppetfile):
- `puppetlabs-stdlib` 9.7.0 — provides utility functions used across the broader module set; `base_utils` itself uses only core Puppet language features
- No other external modules are directly consumed by `base_utils`

**System package dependencies**:
- On Debian/Ubuntu: `vim`, `wget`, `curl`, `jq`, `dnsutils` — all available in standard OS repositories
- On RedHat/CentOS/Rocky: `vim-enhanced`, `wget`, `curl`, `jq`, `bind-utils` — all available in standard OS/EPEL repositories (`jq` may require EPEL on older RHEL versions)

**Service dependencies**:
- None — `base_utils` installs packages and manages a static file; it does not start or manage any services
- Within `profile::base::base`: `base_utils` has no explicit ordering relationship with `chrony`/`rsyslog` management (all three blocks are independent conditionals)

---

## Puppet Facts Used

- `$facts['kernel']` — used by `profile::base::base` to gate NTP and syslog management to Linux hosts only; also used by the `base_utils_info` custom fact to confine itself to Linux
- `$facts['os']['family']` — used implicitly by Hiera hierarchy (`os/%{facts.os.family}.yaml`) to select `Debian.yaml` or `RedHat.yaml` package list
- `$facts['os']['name']` — used in Hiera hierarchy (`os/%{facts.os.name}.yaml`) for name-level overrides; also rendered in `motd.erb`
- `$facts['os']['release']['major']` — used in Hiera hierarchy (`os/%{facts.os.name}/%{facts.os.release.major}.yaml`) for version-specific overrides (no version-specific files exist currently)
- `$facts['os']['release']['full']` — rendered in `motd.erb` (full OS version string)
- `$facts['networking']['fqdn']` — rendered in `motd.erb` (node hostname)
- `$facts['kernelrelease']` — rendered in `motd.erb` (kernel version)
- `$facts['system_uptime']['uptime']` — rendered in `motd.erb` (human-readable uptime)

---

## Template Conversion Notes

### `templates/motd.erb` → `/etc/motd`

- **Render count**: Once per node
- **Variables used**:
  - `@facts['networking']['fqdn']` — node FQDN; Ansible equivalent: `{{ ansible_fqdn }}`
  - `@facts['os']['name']` — OS name; Ansible equivalent: `{{ ansible_distribution }}`
  - `@facts['os']['release']['full']` — full OS release; Ansible equivalent: `{{ ansible_distribution_version }}`
  - `@facts['kernelrelease']` — kernel version string; Ansible equivalent: `{{ ansible_kernel }}`
  - `@facts['system_uptime']['uptime']` — human-readable uptime; Ansible equivalent: `{{ (ansible_uptime_seconds / 86400) | int }} days` (Ansible provides raw seconds, not a pre-formatted string — requires this formatting expression)
- **Ruby logic**: None — pure variable interpolation, no conditionals or loops in the template
- **Ansible conversion**: Use `ansible.builtin.template` with a Jinja2 `.j2` file. The only non-trivial conversion is `system_uptime.uptime` — Puppet provides a pre-formatted string (e.g., `"3 days"`), while Ansible provides `ansible_uptime_seconds` as an integer. Use `{{ (ansible_uptime_seconds / 86400) | int }} days` as the Jinja2 equivalent.

---

## Checks for the Migration

**Files to verify**:
- `/etc/motd` — rendered MOTD banner; verify hostname, OS, kernel, and uptime fields are populated

**Service endpoints to check**:
- None — `base_utils` manages no services

**Templates rendered**:
- `base_utils/motd.erb` → `/etc/motd` — rendered once per node; verify content matches expected banner format

## Pre-flight checks:
```bash
# Verify OS family detection (must return 'Debian' or 'RedHat' to select correct package list)
ansible -m setup -a 'filter=ansible_os_family' <host>

# Verify package availability — Debian/Ubuntu hosts
apt-cache show vim wget curl jq dnsutils

# Verify package availability — RedHat/CentOS/Rocky hosts
yum info vim-enhanced wget curl jq bind-utils
# Confirm EPEL is enabled for jq on RHEL 7/8 if not found above
yum repolist | grep epel

# Verify MOTD content after run
cat /etc/motd
# Expected: managed banner with hostname, OS, kernel, uptime fields populated

# Verify packages installed — Debian/Ubuntu hosts
dpkg -l vim wget curl jq dnsutils

# Verify packages installed — RedHat/CentOS/Rocky hosts
rpm -q vim-enhanced wget curl jq bind-utils

# Idempotency check: run the playbook twice; second run must report 0 changes
```