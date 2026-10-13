---
source-path: site/modules/common/base_utils
---

# Migration Plan: base_utils

**TLDR**: `base_utils` is a host-baseline Puppet class that conditionally manages `/etc/motd` and iterates over `base_utils::utility_packages` to install packages. The supplied execution-tree analysis confirms the MOTD file resource and package loop, but the Hiera values, template contents, supporting components, credentials, and complete 71-file inventory were not included in the validation evidence. The Ansible equivalent should use role defaults, OS-specific variables, a conditional template task, and a package loop while verifying the reported Hiera values before implementation.

## Service Type and Instances

**Service Type**: Operating-system baseline utilities and MOTD configuration.

**Configured Instances**:

- **Debian-family host**
  - Purpose: Manage the host MOTD and install Debian utility packages.
  - Location/Path: `/etc/motd`
  - Port/Socket: None
  - Key Config:
    - MOTD management is reported as enabled.
    - Reported packages: `vim`, `wget`, `curl`, `jq`, `dnsutils`.
    - The package list requires confirmation from the Debian Hiera data.

- **RedHat-family host**
  - Purpose: Manage the host MOTD and install RedHat utility packages.
  - Location/Path: `/etc/motd`
  - Port/Socket: None
  - Key Config:
    - MOTD management is reported as enabled.
    - Reported packages: `vim-enhanced`, `wget`, `curl`, `jq`, `bind-utils`.
    - The package list requires confirmation from the RedHat Hiera data.

- **Unsupported or unmatched OS hierarchy**
  - Purpose: Manage the common MOTD configuration without installing utility packages.
  - Location/Path: `/etc/motd`
  - Port/Socket: None
  - Key Config:
    - The reported common package default is an empty array.
    - The package loop runs zero times when the array is empty.
    - The common defaults require confirmation from the Hiera analysis.

## File Structure

The supplied directory listing is incomplete relative to the reported 71 analyzed files. Only the following paths were explicitly identified:

```text
site/modules/common/base_utils/
├── manifests/
│   └── init.pp
├── templates/
│   └── motd.erb                  # Referenced by the manifest; not present in supplied listing
└── data/
    ├── common.yaml                # Referenced data file; not present in supplied listing
    └── os/
        ├── Debian.yaml            # Referenced data file; not present in supplied listing
        └── RedHat.yaml            # Referenced data file; not present in supplied listing
```

The remaining analyzed files must be classified before migration as additional manifests, templates, Hiera data, tests, supporting components, or unused files. Their paths were not supplied and cannot be reconstructed accurately.

## Module Explanation

The supplied execution-tree analysis confirms the following execution order:

1. **`base_utils`** (`site/modules/common/base_utils/manifests/init.pp`):
   - Evaluates the `manage_motd` parameter.
   - When enabled, manages `file[/etc/motd]`.
   - Uses the reported template value `base_utils/motd.erb`.
   - Sets the file owner to `root`, group to `root`, and mode to `0644`.
   - Iterates over the `utility_packages` array and creates one installed package resource per item.
   - Defines no explicit Puppet ordering arrows.
   - Does not include or contain other classes.
   - Does not manage a service.
   - Does not define restart or reload handlers.

   **Conditional MOTD resource**:
   - Resource: `file[/etc/motd]`
   - Ensure: `file`
   - Owner: `root`
   - Group: `root`
   - Mode: `0644`
   - Source: reported template value `base_utils/motd.erb`
   - Reported render count: one render per managed host when enabled
   - Notifications and subscriptions: none identified

   **Utility package loop**:

   - **Debian-family expansion** — reported five iterations:
     - `package[vim]` — ensure: `installed`
     - `package[wget]` — ensure: `installed`
     - `package[curl]` — ensure: `installed`
     - `package[jq]` — ensure: `installed`
     - `package[dnsutils]` — ensure: `installed`

   - **RedHat-family expansion** — reported five iterations:
     - `package[vim-enhanced]` — ensure: `installed`
     - `package[wget]` — ensure: `installed`
     - `package[curl]` — ensure: `installed`
     - `package[jq]` — ensure: `installed`
     - `package[bind-utils]` — ensure: `installed`

   - **Common fallback expansion**:
     - Reported loop count: zero
     - Package resources: none
     - The empty default list requires confirmation from Hiera analysis.

## Variables

**Variable Flow Summary**: 3 class parameters across common and OS-specific Hiera levels. The execution-tree analysis confirms that the class consumes these parameters, but the supplied validation evidence does not verify their Hiera definitions or resolved values.

### Variable Definitions

**common.yaml (defaults)** → Migration note: Reported base defaults for all nodes; values require verification against the actual file.

- `base_utils::manage_motd`: `true` (type: boolean; unverified)
- `base_utils::motd_template`: `base_utils/motd.erb` (type: string; unverified)
- `base_utils::utility_packages`: `[]` (type: array of strings; unverified)

**os/Debian.yaml (OS-specific)** → Migration note: Reported Debian-family package override; file and values require verification.

- `base_utils::utility_packages`: `[vim, wget, curl, jq, dnsutils]` (type: array of strings; unverified)

**os/RedHat.yaml (OS-specific)** → Migration note: Reported RedHat-family package override; file and values require verification.

- `base_utils::utility_packages`: `[vim-enhanced, wget, curl, jq, bind-utils]` (type: array of strings; unverified)

### Hiera → Ansible Mapping

Recommended role defaults:

```yaml
# roles/base_utils/defaults/main.yml
base_utils_manage_motd: true
base_utils_motd_template: base_utils/motd.erb
base_utils_utility_packages: []
```

Recommended Debian variables:

```yaml
# group_vars/Debian.yml
base_utils_utility_packages:
  - vim
  - wget
  - curl
  - jq
  - dnsutils
```

Recommended RedHat variables:

```yaml
# group_vars/RedHat.yml
base_utils_utility_packages:
  - vim-enhanced
  - wget
  - curl
  - jq
  - bind-utils
```

The Ansible role must preserve the reported Puppet first-value replacement behavior: OS-specific package lists replace the common empty list rather than being appended to it.

### Variable Migration Summary

- **Common defaults**: 3 reported variables from `common.yaml`; values unverified
- **OS-specific variables**: 1 reported variable overridden for Debian and RedHat; values unverified
- **Environment-specific variables**: 0 supplied
- **Host-specific variables**: 0 supplied
- **Encrypted variables**: 0 identified in the supplied execution-tree summary; full credential analysis was not provided

### Cross-Level Overrides

Variables reported at multiple Hiera levels:

- **`base_utils::utility_packages`**:
  - Defined in common, Debian, and RedHat data.
  - Reported merge strategy: `first`.
  - Reported behavior: OS-specific values replace the common empty list rather than being concatenated.
  - Hiera definitions and merge behavior require verification.

- **`base_utils::manage_motd`**:
  - Reported as defined only in common data.
  - Verification unavailable.

- **`base_utils::motd_template`**:
  - Reported as defined only in common data.
  - Verification unavailable.

### Merge Strategy Notes

- Variables using `hash` merge: Hash values from multiple levels are merged using a shallow merge.
- Variables using `deep` merge: Hash values are recursively merged.
- Variables using `first` merge: The first value found wins and values are not merged.
- The reported `base_utils::utility_packages` behavior uses `first` semantics, subject to Hiera verification.

## Dependencies

**External module dependencies**:

- `puppetlabs-stdlib` `9.7.0`
- `puppetlabs-concat` `9.0.2`
- `puppetlabs-firewall` `8.1.3`
- `puppetlabs-vcsrepo` `6.1.0`
- `puppet-redis` `11.0.0`
- `puppetlabs-apt` `9.4.0`

None are referenced by the supplied `base_utils` execution-tree summary. Dependency usage should be confirmed against the complete 71-file inventory.

**System package dependencies**:

- Debian-family, reported:
  - `vim`
  - `wget`
  - `curl`
  - `jq`
  - `dnsutils`

- RedHat-family, reported:
  - `vim-enhanced`
  - `wget`
  - `curl`
  - `jq`
  - `bind-utils`

The package names require confirmation from the corresponding Hiera data files.

**Service dependencies**:

- None identified.
- No service is enabled, started, restarted, or reloaded by the supplied execution tree.

## Puppet Facts Used

No explicit Puppet fact references were identified in `site/modules/common/base_utils/manifests/init.pp`.

OS-specific package selection is reported as Hiera-driven rather than explicitly fact-driven in the manifest. The Ansible implementation may use inventory group variables, gathered OS facts, or both, but the selected mechanism must preserve the verified Debian and RedHat mappings.

## Template Conversion Notes

### `base_utils/motd.erb`

- Reported source value: `base_utils/motd.erb`
- Exact filesystem path: not present in the supplied directory listing
- Destination: `/etc/motd`
- Owner: `root`
- Group: `root`
- Mode: `0644`
- Reported render count: one render per host when MOTD management is enabled
- Template variables and Ruby logic: not available in the supplied analysis
- Template contents and non-trivial logic must be reviewed before migration

Recommended Ansible task structure:

```yaml
- name: Deploy /etc/motd for Debian-family host
  ansible.builtin.template:
    src: motd.erb
    dest: /etc/motd
    owner: root
    group: root
    mode: "0644"
  when:
    - ansible_facts.os_family == "Debian"
    - base_utils_manage_motd | bool

- name: Deploy /etc/motd for RedHat-family host
  ansible.builtin.template:
    src: motd.erb
    dest: /etc/motd
    owner: root
    group: root
    mode: "0644"
  when:
    - ansible_facts.os_family == "RedHat"
    - base_utils_manage_motd | bool

- name: Deploy /etc/motd for unmatched OS hierarchy
  ansible.builtin.template:
    src: motd.erb
    dest: /etc/motd
    owner: root
    group: root
    mode: "0644"
  when:
    - ansible_facts.os_family not in ["Debian", "RedHat"]
    - base_utils_manage_motd | bool
```

## PuppetDB Dependencies

No PuppetDB dependencies were identified in the supplied execution-tree summary:

- No exported resources (`@@`) were identified.
- No virtual resources (`@`) were identified.
- No resource collectors (`<<| |>>`) were identified.
- No `puppetdb_query()` calls were identified.

The full PuppetDB analysis was not supplied, so these findings require confirmation against the complete analyzed-file inventory.

## Credentials

No credentials were identified in the supplied execution-tree summary.

The migration plan reports no passwords, tokens, private keys, certificates, or encrypted Hiera values associated with the `base_utils` class. Credentials from unrelated dependency modules, including Redis-related parameters, are out of scope unless the complete file inventory shows that `base_utils` references them.

## Checks for the Migration

**Files to verify**:

- `site/modules/common/base_utils/manifests/init.pp`
- Referenced template value `base_utils/motd.erb`
- `site/modules/common/base_utils/data/common.yaml`
- `site/modules/common/base_utils/data/os/Debian.yaml`
- `site/modules/common/base_utils/data/os/RedHat.yaml`
- Complete inventory of the reported 71 analyzed files
- Any additional manifests, templates, Hiera data, tests, facts, functions, custom types, or plans found in the complete inventory

**Service endpoints to check**:

- None.
- This module does not manage a service or network listener.

**Templates rendered**:

- `/etc/motd` from the reported `base_utils/motd.erb`: one render per managed host when enabled.
- The render count and template contents require confirmation from template analysis.

## Pre-flight checks

```bash
# Confirm the migration source files that were explicitly identified
test -f site/modules/common/base_utils/manifests/init.pp
test -f site/modules/common/base_utils/data/common.yaml
test -f site/modules/common/base_utils/data/os/Debian.yaml
test -f site/modules/common/base_utils/data/os/RedHat.yaml

# Confirm the referenced template after locating its exact source path
find site/modules/common/base_utils -type f -name 'motd.erb' -print

# Confirm Debian-family package availability
ansible Debian -b -m ansible.builtin.package_facts
ansible Debian -b -m ansible.builtin.command -a \
  'sh -c "command -v vim && command -v wget && command -v curl && command -v jq && command -v dig || command -v nslookup"'

# Confirm RedHat-family package availability
ansible RedHat -b -m ansible.builtin.package_facts
ansible RedHat -b -m ansible.builtin.command -a \
  'sh -c "command -v vim-enhanced || command -v vim; command -v wget; command -v curl; command -v jq; command -v dig || command -v nslookup"'

# Verify Debian-family instance configuration
ansible Debian -b -m ansible.builtin.stat -a 'path=/etc/motd'
ansible Debian -b -m ansible.builtin.package_facts

# Verify RedHat-family instance configuration
ansible RedHat -b -m ansible.builtin.stat -a 'path=/etc/motd'
ansible RedHat -b -m ansible.builtin.package_facts

# Verify unmatched-OS instance configuration
ansible unmatched_os -b -m ansible.builtin.stat -a 'path=/etc/motd'
ansible unmatched_os -b -m ansible.builtin.package_facts

# Validate /etc/motd ownership and permissions on Debian-family hosts
ansible Debian -b -m ansible.builtin.command -a \
  'stat -c "%U %G %a %n" /etc/motd'

# Validate /etc/motd ownership and permissions on RedHat-family hosts
ansible RedHat -b -m ansible.builtin.command -a \
  'stat -c "%U %G %a %n" /etc/motd'

# Validate /etc/motd ownership and permissions on unmatched-OS hosts
ansible unmatched_os -b -m ansible.builtin.command -a \
  'stat -c "%U %G %a %n" /etc/motd'

# Confirm no service endpoint is required
ansible all -b -m ansible.builtin.service_facts
```