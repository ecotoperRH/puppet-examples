---
source-path: site/modules/common/base_utils
---

# Migration Plan: base_utils

**TLDR**: `base_utils` is a lightweight "common baseline" Puppet module that runs on every Linux node in the `role::app_stack` role chain. It does two things: (1) writes a managed `/etc/motd` banner populated with system facts, and (2) installs a small set of OS-family-specific utility packages (`vim`/`vim-enhanced`, `wget`, `curl`, `jq`, `dnsutils`/`bind-utils`). It is invoked via `profile::base::base` (guarded by `$manage_utils = true`) and ships custom Puppet type aliases, a null-coalescing function, a port-normalisation function, a custom Facter fact, and two Bolt Plans — none of which require custom Ansible modules to replicate.

---

## Service Type and Instances

**Service Type**: OS Baseline / Node Hardening (no long-running service managed by this module itself)

**Configured Instances**:
- **motd**: Managed Message-of-the-Day banner
  - Location/Path: `/etc/motd`
  - Key Config: rendered from `base_utils/motd.erb`; shows FQDN, OS name+version, kernel release, uptime

- **utility-packages-debian**: Utility packages on Debian/Ubuntu hosts
  - `vim` — ensure: `installed`
  - `wget` — ensure: `installed`
  - `curl` — ensure: `installed`
  - `jq` — ensure: `installed`
  - `dnsutils` — ensure: `installed`

- **utility-packages-redhat**: Utility packages on RedHat/CentOS hosts
  - `vim-enhanced` — ensure: `installed`
  - `wget` — ensure: `installed`
  - `curl` — ensure: `installed`
  - `jq` — ensure: `installed`
  - `bind-utils` — ensure: `installed`

---

## File Structure

```
site/
├── modules/
│   └── common/
│       └── base_utils/
│           ├── manifests/
│           │   └── init.pp
│           ├── templates/
│           │   └── motd.erb
│           ├── data/
│           │   ├── common.yaml
│           │   └── os/
│           │       ├── Debian.yaml
│           │       └── RedHat.yaml
│           ├── hiera.yaml
│           ├── functions/
│           │   ├── ensure_value.pp
│           │   └── normalize_port.pp
│           ├── types/
│           │   ├── ensure_value.pp
│           │   ├── log_level.pp
│           │   └── port.pp
│           ├── plans/
│           │   ├── health_check.pp
│           │   └── rolling_restart.pp
│           └── lib/
│               └── facter/
│                   └── base_utils_info.rb
├── profile/
│   └── manifests/
│       └── base/
│           └── base.pp
└── role/
    └── manifests/
        └── app_stack.pp
```

---

## Module Explanation

The module performs operations in this order:

**IMPORTANT: Full paths from the File Structure section are used throughout.**

1. **role::app_stack** (`site/role/manifests/app_stack.pp`):
   - Conditional: `if $facts['kernel'].downcase == 'linux'` → `exec[default]` (Linux-only exec resource)
   - `include ::profile::base::base`
   - `include ::profile::app::stack`
   - Ordering: `Class['::profile::base::base'] -> Class['::profile::app::stack']` — base utilities complete before the application stack starts

2. **profile::base::base** (`site/profile/manifests/base/base.pp`):
   - Class parameters (all resolved via Hiera `first` merge):
     - `$manage_utils` → `true` (default)
     - `$manage_ntp` → `true` (default)
     - `$manage_syslog` → `true` (default)
   - Conditional block 1 — `if $manage_utils` (evaluates `true`): `include base_utils`
   - Conditional block 2 — `if $manage_ntp and $facts['kernel'] == 'Linux'` (evaluates `true` on Linux):
     - `package 'chrony'` → ensure: `installed`
     - `service 'chronyd'` → ensure: `running`, enable: `true`
   - Conditional block 3 — `if $manage_syslog and $facts['kernel'] == 'Linux'` (evaluates `true` on Linux):
     - `package 'rsyslog'` → ensure: `installed`
     - `service 'rsyslog'` → ensure: `running`, enable: `true`

3. **base_utils** (`site/modules/common/base_utils/manifests/init.pp`):
   - Class parameters resolved from Hiera:
     - `$manage_motd` → `true` (from `data/common.yaml`)
     - `$motd_template` → `'base_utils/motd.erb'` (from `data/common.yaml`)
     - `$utility_packages` → OS-family dependent; `first` merge strategy — OS-level value completely replaces the `common.yaml` empty-array default
   - Conditional block — `if $manage_motd` (evaluates `true`):
     - `file '/etc/motd'` (template `base_utils/motd.erb`) → ensure: `file`, owner: `root`, group: `root`, mode: `0644`
     - Template renders once per node; variables used:
       - `@facts['networking']['fqdn']` — node's fully-qualified domain name
       - `@facts['os']['name']` — OS name (e.g., `Ubuntu`, `CentOS`)
       - `@facts['os']['release']['full']` — full OS release string (e.g., `22.04`, `7.9.2009`)
       - `@facts['kernelrelease']` — kernel version string (e.g., `5.15.0-91-generic`)
       - `@facts['system_uptime']['uptime']` — human-readable uptime string (e.g., `3 days`)
   - Loop — `$utility_packages.each |String $pkg|`:
     - *On Debian/Ubuntu hosts* — loop runs **5 times** (from `data/os/Debian.yaml`):
       - `package 'vim'` → ensure: `installed`
       - `package 'wget'` → ensure: `installed`
       - `package 'curl'` → ensure: `installed`
       - `package 'jq'` → ensure: `installed`
       - `package 'dnsutils'` → ensure: `installed`
     - *On RedHat/CentOS hosts* — loop runs **5 times** (from `data/os/RedHat.yaml`):
       - `package 'vim-enhanced'` → ensure: `installed`
       - `package 'wget'` → ensure: `installed`
       - `package 'curl'` → ensure: `installed`
       - `package 'jq'` → ensure: `installed`
       - `package 'bind-utils'` → ensure: `installed`
     - *On unrecognised OS families* — loop runs **0 times** (empty array fallback from `data/common.yaml`); no packages are installed

---

## Variables

**Variable Flow Summary**: 3 variables across 3 Hiera levels (1 module common + 2 OS-family overrides)

### Variable Definitions

**common.yaml (module defaults — lowest priority)** → Migration note: Base defaults applied to all nodes regardless of OS; the `utility_packages` empty array here acts as a safe fallback for unrecognised OS families
- `base_utils::manage_motd`: `true` (type: boolean)
- `base_utils::motd_template`: `'base_utils/motd.erb'` (type: string)
- `base_utils::utility_packages`: `[]` (type: array — empty fallback for unrecognised OS families)

**os/Debian.yaml (OS-family level — higher priority than common)** → Migration note: OS-specific variables, loaded conditionally when `$facts['os']['family'] == 'Debian'`; replaces the common.yaml empty array entirely (first-merge, no concatenation)
- `base_utils::utility_packages`: `['vim', 'wget', 'curl', 'jq', 'dnsutils']` (type: array)

**os/RedHat.yaml (OS-family level — higher priority than common)** → Migration note: OS-specific variables, loaded conditionally when `$facts['os']['family'] == 'RedHat'`; replaces the common.yaml empty array entirely (first-merge, no concatenation)
- `base_utils::utility_packages`: `['vim-enhanced', 'wget', 'curl', 'jq', 'bind-utils']` (type: array)

### Variable Migration Summary

- **Common defaults**: 3 variables (`manage_motd`, `motd_template`, `utility_packages` fallback) from `common.yaml` (base configuration for all nodes)
- **OS-specific variables**: 2 variables (`utility_packages` for Debian and RedHat families) that vary by OS family
- **Environment-specific variables**: 0 variables
- **Host-specific variables**: 0 variables
- **Encrypted variables**: 0 variables (no eyaml or Sensitive types in this module)

### Cross-Level Overrides

- **`base_utils::utility_packages`**: defined at `common.yaml` (empty array `[]`) AND `os/Debian.yaml` AND `os/RedHat.yaml`; merge strategy: `first` — the OS-family file wins outright; no array merging occurs; the `common.yaml` empty array is only used when no OS-family file matches

### Merge Strategy Notes

- Variables using `first` (default) — First value found wins, no merging; applies to all variables in this module including `utility_packages`, where the OS-family file completely replaces the common.yaml default

---

## Custom Types and Providers

**Custom Facter fact: `base_utils_info`** (`site/modules/common/base_utils/lib/facter/base_utils_info.rb`)
- Linux-only (confined to `kernel: 'Linux'`)
- Returns a hash with:
  - `curl` (Boolean) — whether `curl` package is installed (via `rpm -q` or `dpkg -l`)
  - `wget` (Boolean) — whether `wget` package is installed
  - `jq` (Boolean) — whether `jq` package is installed
  - `vim` (Boolean) — whether `vim` package is installed
  - `uptime_seconds` (Integer) — system uptime read from `/proc/uptime`
- **Ansible equivalent**: No custom module needed. Use `ansible.builtin.package_facts` to populate `ansible_facts.packages` for package presence checks; `ansible_uptime_seconds` is already exposed by `ansible.builtin.setup`.

**Puppet function: `base_utils::ensure_value`** (`site/modules/common/base_utils/functions/ensure_value.pp`)
- Null-coalescing guard: returns `$input` if non-empty string, otherwise returns `$default_value`
- **Ansible equivalent**: Jinja2 `{{ input | default(default_value, true) }}` filter (the `true` boolean treats empty strings as missing)

**Puppet function: `base_utils::normalize_port`** (`site/modules/common/base_utils/functions/normalize_port.pp`)
- Coerces a `String` or `Integer` port to a validated `Integer` within `Base_utils::Port` range (1–65535)
- **Ansible equivalent**: Jinja2 `{{ port | int }}` for coercion; add an `ansible.builtin.assert` task for range validation (`port >= 1 and port <= 65535`)

**Type alias: `Base_utils::Ensure_value`** (`site/modules/common/base_utils/types/ensure_value.pp`)
- `Enum['present', 'absent', 'installed', 'latest', 'purged']`
- **Ansible equivalent**: Document allowed values in role `argument_specs`; enforce with `ansible.builtin.assert` or module `state:` parameter constraints

**Type alias: `Base_utils::Log_level`** (`site/modules/common/base_utils/types/log_level.pp`)
- `Enum['debug', 'info', 'notice', 'warning', 'error', 'critical', 'alert', 'emergency']`
- **Ansible equivalent**: `choices:` in module `argument_spec` or `ansible.builtin.assert` with `in` test

**Type alias: `Base_utils::Port`** (`site/modules/common/base_utils/types/port.pp`)
- `Integer[1, 65535]`
- **Ansible equivalent**: `ansible.builtin.assert` task: `that: "port | int >= 1 and port | int <= 65535"`

**Bolt Plan: `base_utils::health_check`** (`site/modules/common/base_utils/plans/health_check.pp`)
- Runs `base_utils::check_service` Bolt task on all targets; filters for non-running services; reports healthy/unhealthy
- Default service: `sshd`
- **Ansible equivalent**: Playbook using `ansible.builtin.service_facts` + `ansible.builtin.assert` or `ansible.builtin.fail` to gate on service state

**Bolt Plan: `base_utils::rolling_restart`** (`site/modules/common/base_utils/plans/rolling_restart.pp`)
- Sequentially restarts a named systemd service across targets; verifies service running after each restart; sleeps `delay_seconds` (default: 30) between hosts; fails early if post-restart check fails
- **Ansible equivalent**: Playbook with `serial: 1`, `ansible.builtin.systemd` (state: restarted), `ansible.builtin.service_facts` for verification, `ansible.builtin.pause` for inter-host delay

---

## Dependencies

**External module dependencies**:
- `puppetlabs-stdlib` 9.7.0 — provides utility functions (e.g., `lookup`); Ansible equivalent: built-in Jinja2 filters
- `puppetlabs-concat` 9.0.2 — not directly used by `base_utils` itself
- `puppetlabs-firewall` 8.1.3 — not directly used by `base_utils` itself
- `puppetlabs-vcsrepo` 6.1.0 — not directly used by `base_utils` itself
- `puppet-redis` 11.0.0 — not directly used by `base_utils` itself
- `puppetlabs-apt` 9.4.0 — not directly used by `base_utils` itself

**System package dependencies** (installed by this module):
- Debian/Ubuntu: `vim`, `wget`, `curl`, `jq`, `dnsutils`
- RedHat/CentOS: `vim-enhanced`, `wget`, `curl`, `jq`, `bind-utils`
- All Linux (managed by `profile::base::base`, not `base_utils` directly): `chrony` (NTP), `rsyslog` (syslog)

**Service dependencies**:
- `profile::base::base` uses `include base_utils` (no containment), so `base_utils` resources are not automatically ordered relative to NTP/syslog resources within the profile
- Role-level ordering: `Class['::profile::base::base'] -> Class['::profile::app::stack']` — base utilities complete before the application stack starts

---

## Puppet Facts Used

- `$facts['kernel']` — kernel name string (e.g., `'Linux'`); used in `role::app_stack` and `profile::base::base` to gate Linux-only resources
- `$facts['networking']['fqdn']` — node FQDN; rendered into `/etc/motd` via template
- `$facts['os']['name']` — OS name (e.g., `Ubuntu`, `CentOS`); rendered into `/etc/motd`; also drives Hiera OS-family lookup path (`os/%{facts.os.name}.yaml`)
- `$facts['os']['family']` — OS family (e.g., `Debian`, `RedHat`); drives Hiera OS-family lookup path (`os/%{facts.os.family}.yaml`)
- `$facts['os']['release']['full']` — full OS release string; rendered into `/etc/motd`
- `$facts['os']['release']['major']` — major OS release; drives Hiera OS+major-release lookup path (`os/%{facts.os.family}/%{facts.os.release.major}.yaml`)
- `$facts['kernelrelease']` — kernel version string; rendered into `/etc/motd`
- `$facts['system_uptime']['uptime']` — human-readable uptime; rendered into `/etc/motd`
- `fact('environment')` — Puppet environment name; used in `profile::app::stack` (outside `base_utils` scope)

---

## Template Conversion Notes

**`base_utils/motd.erb`** (`site/modules/common/base_utils/templates/motd.erb`) → `/etc/motd` (rendered **once per node**)

Variables referenced:
- `@facts['networking']['fqdn']` — FQDN string
- `@facts['os']['name']` — OS name string
- `@facts['os']['release']['full']` — full release string
- `@facts['kernelrelease']` — kernel version string
- `@facts['system_uptime']['uptime']` — uptime string

No Ruby logic blocks, no conditionals, no loops — pure variable interpolation. Straightforward conversion to an Ansible `ansible.builtin.copy` task with `content:` using a Jinja2 template:

```yaml
- name: Write /etc/motd
  ansible.builtin.copy:
    dest: /etc/motd
    owner: root
    group: root
    mode: '0644'
    content: |
      ========================================
        Managed by Ansible
        Hostname: {{ ansible_fqdn }}
        OS:       {{ ansible_distribution }} {{ ansible_distribution_version }}
        Kernel:   {{ ansible_kernel }}
        Uptime:   {{ ansible_uptime_seconds | int // 86400 }} days
      ========================================
```

Ansible fact mappings:
- `@facts['networking']['fqdn']` → `ansible_fqdn`
- `@facts['os']['name']` → `ansible_distribution`
- `@facts['os']['release']['full']` → `ansible_distribution_version`
- `@facts['kernelrelease']` → `ansible_kernel`
- `@facts['system_uptime']['uptime']` → derive from `ansible_uptime_seconds` (no direct human-readable equivalent; compute days/hours/minutes via Jinja2 arithmetic or use `ansible_uptime_seconds` directly)

---

## Checks for the Migration

**Files to verify**:
- `/etc/motd` — must exist, owner `root`, group `root`, mode `0644`, content contains node FQDN and OS info

**Service endpoints to check**:
- No network ports or sockets managed by this module

**Templates rendered**:
- `base_utils/motd.erb` → `/etc/motd` — rendered 1 time per node

## Pre-flight checks:

```bash
# --- motd instance ---
# Verify /etc/motd exists with correct ownership and permissions
stat /etc/motd
# Verify motd content contains expected fields
cat /etc/motd

# --- utility-packages-debian (run on Debian/Ubuntu hosts) ---
dpkg -l vim
dpkg -l wget
dpkg -l curl
dpkg -l jq
dpkg -l dnsutils

# --- utility-packages-redhat (run on RedHat/CentOS hosts) ---
rpm -q vim-enhanced
rpm -q wget
rpm -q curl
rpm -q jq
rpm -q bind-utils

# --- NTP (managed by profile::base::base, not base_utils directly) ---
systemctl status chronyd

# --- Syslog (managed by profile::base::base, not base_utils directly) ---
systemctl status rsyslog
```