# MIGRATION FROM PUPPET TO ANSIBLE

## Executive Summary

This repository is a **Puppet control repository** targeting Linux infrastructure (Ubuntu 24.04 and Rocky Linux 9) across two environments (production, staging) and multiple datacenters. It provisions three application tiers — a load-balancer (HAProxy), an application stack (Python/Flask + PostgreSQL + Git-deployed code), and a Redis cluster — plus a shared base profile (chrony, rsyslog, base utilities).

The migration scope covers **7 distinct Puppet modules** (4 in `modules/`, 3 additional active copies in `site/modules/linux/`), **3 role manifests**, **4 profile wrapper manifests**, a multi-level Hiera data hierarchy (eyaml-encrypted secrets at the node tier), and supporting tooling (Vagrant, container-based CI). The repository also contains **25 confirmed bugs** that must be resolved either before or in parallel with the Ansible migration.

**Complexity**: High — multi-OS targeting (Debian/RedHat families), multi-environment Hiera data, eyaml secrets, PuppetDB dynamic inventory queries, custom Facter facts, and a split module layout (`modules/` vs `site/modules/linux/`) that creates a dual-maintenance burden.

**Estimated Timeline**: 10–14 weeks for a full migration with parallel validation.

---

## Module Migration Plan

This repository contains Puppet modules, profiles, and roles that each require individual migration planning.

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:** All paths below have been confirmed via `list_directory` and `file_search` exploration of the repository.

---

- **profile_haproxy** (modules/ copy):
    - Description: HAProxy load-balancer profile managing package installation, frontend/backend configuration, SSL termination, health checks, stick-tables, stats endpoint, error pages, logrotate, and OS-specific firewall rules (ufw on Debian, firewalld on RedHat). Supports multi-datacenter backend server lists and per-environment tuning (maxconn, TLS version, stick-table toggle).
    - Path: `modules/profile_haproxy`
    - Technology: Puppet
    - Key Features: ERB template for `haproxy.cfg`, Hiera-driven backend server lists with deep merge, `firewall.pp` with ufw/firewalld branching, stats socket on configurable port, SSL via Let's Encrypt or provided cert, logrotate integration, OS data files for Debian and RedHat

- **profile_haproxy** (active/site copy):
    - Description: Identical in purpose to the `modules/` copy; this is the **active production version** loaded first by `environment.conf` modulepath (`site/modules/linux` takes precedence). Contains the same HAProxy configuration logic with the same Hiera data hierarchy (`common`, `environment`, `cluster`, `datacenter`, `nodes`, `os` tiers).
    - Path: `site/modules/linux/profile_haproxy`
    - Technology: Puppet
    - Key Features: Same as above; additionally confirmed to have `data/os/RedHat.yaml` (firewalld, selinux_enabled true, policycoreutils-python-utils); cluster-level data for `haproxy_prod_fra` (maxconn 32768, TLSv1.3, internal_monitoring backend); datacenter data for `dc1_fra` (log server 10.100.1.50, Frankfurt backend IPs); node-level data for `lb01.fra.example.com` (stats_port 9001, api backend weight overrides)

- **profile_app_stack** (modules/ copy):
    - Description: Full Python/Flask application stack profile covering application user/group, directory layout, virtualenv, pip package installation, Git-based code deployment (via vcsrepo), PostgreSQL client libraries, Gunicorn systemd service, logrotate, and Prometheus node-exporter monitoring integration. Parameterised for app name, repo URL, DB credentials, and environment name.
    - Path: `modules/profile_app_stack`
    - Technology: Puppet
    - Key Features: `app.env.erb` template (environment variables including DB password), `manifests/install.pp` (vcsrepo + virtualenv), `manifests/database.pp` (libpq-dev/postgresql-devel OS-conditional), `manifests/python.pp` (OS-conditional build tools), `manifests/monitoring.pp` (Prometheus scrape config), `manifests/service.pp` (systemd unit), `manifests/logrotate.pp`

- **profile_app_stack** (active/site copy):
    - Description: Active production version of the app stack profile, loaded by `site/modules/linux` modulepath precedence. Identical structure and bugs to the `modules/` copy.
    - Path: `site/modules/linux/profile_app_stack`
    - Technology: Puppet
    - Key Features: Same as above; confirmed `hiera.yaml` with `%{::environment}` deprecation bug (fix #7), `app.env.erb` with `@facts['environment']` bug (fix #9), `manifests/monitoring.pp` with `$facts['environment']` bug (fix #13), OS-conditional package gaps in `python.pp` (fix #15) and `database.pp` (fix #17)

- **profile_redis_cluster** (modules/ copy):
    - Description: Redis cluster profile managing Redis installation, configuration, replication topology detection, and log directory. Uses a custom Facter fact (`redis_role.rb`) to detect primary vs. replica role by inspecting `/etc/redis/conf.d/replica.conf`. Queries PuppetDB for peer node IPs to build the replica-of configuration dynamically.
    - Path: `modules/profile_redis_cluster`
    - Technology: Puppet
    - Key Features: `manifests/init.pp` (4 hardcoded params, `puppetdb_query()` stub call), `manifests/install.pp` (puppet-redis class wrapper, `/var/log/redis` directory), `templates/redis.conf.erb` (full Redis config with bind address from `$facts['networking']['fqdn']`), `lib/facter/redis_role.rb` (custom fact)

- **profile_redis_cluster** (active/site copy):
    - Description: Active production version of the Redis cluster profile. Identical to `modules/` copy; loaded by `site/modules/linux` modulepath precedence.
    - Path: `site/modules/linux/profile_redis_cluster`
    - Technology: Puppet
    - Key Features: Same as above; `metadata.json` v3.1.0 supports RedHat 8/9 and Ubuntu 22.04/24.04; Puppet version cap `< 9.0.0` needs updating to `< 10.0.0` (fix #21); own `Puppetfile` pinning stdlib 9.6.0, puppet-redis 11.0.0, puppetlabs-apt 9.4.0

- **puppetdb_query_stub** (modules/ copy):
    - Description: Stub module that provides a no-op implementation of the `puppetdb_query()` function used by `profile_redis_cluster`. Allows the module to be tested and applied without a live PuppetDB instance. Returns an empty array, meaning Redis replication is not configured in stub mode.
    - Path: `modules/puppetdb_query_stub`
    - Technology: Puppet
    - Key Features: Single function stub; critical for CI/test environments; must be replaced in Ansible by a real dynamic inventory mechanism (e.g., `ansible.builtin.add_host` or group vars)

- **base_utils** (site/modules/common):
    - Description: Common base utilities profile providing OS-agnostic package installation for baseline tooling (curl, vim, htop, etc.). Referenced by `site/profile/manifests/base/base.pp` via Hiera lookup for package list. Supports both Debian and RedHat package name variants.
    - Path: `site/modules/common/base_utils`
    - Technology: Puppet
    - Key Features: Hiera-driven package list, `metadata.json` Puppet cap `< 9.0.0` needs fix (fix #22)

---

### Infrastructure Files

- `Puppetfile`: Root-level r10k/g10k dependency lockfile. Pins: `puppetlabs-stdlib 9.7.0`, `puppetlabs-concat 9.0.2`, `puppetlabs-firewall 8.1.3`, `puppetlabs-vcsrepo 6.1.0`, `puppet-redis 11.0.0`, `puppetlabs-apt 9.4.0`. All six must be replaced with equivalent Ansible collections or roles.
- `environment.conf`: Defines modulepath `site/modules/linux:site/modules/common:site:modules:$basemodulepath`. The ordering means `site/modules/linux/` versions shadow `modules/` — critical for understanding which code is active.
- `hiera.yaml` (root): Five-tier Hiera hierarchy — `nodes/%{trusted.certname}` (eyaml), `environment/%{facts.environment}`, `cluster/%{facts.cluster}`, `datacenter/%{facts.datacenter}`, `common`. Uses `hiera-eyaml` for node-level secrets. This entire hierarchy must be replicated in Ansible via group_vars/host_vars with Ansible Vault replacing eyaml.
- `data/environment/production.yaml`: NTP server pool overrides and rsyslog remote target for production.
- `data/environment/staging.yaml`: NTP server pool overrides and rsyslog remote target for staging.
- `Vagrantfile`: Ubuntu 24.04 (`generic/ubuntu2404`), libvirt provider, rsyncs repo to `/puppet-repo` on guest. Used for local development testing.
- `vagrant-provision.sh`: Installs Puppet 8 agent on Ubuntu 24.04, installs 5 Forge modules, copies `modules/profile_haproxy`, `modules/profile_app_stack`, `modules/profile_redis_cluster`, `modules/puppetdb_query_stub` — **BUG**: misses `site/modules/linux/` and `site/modules/common/` paths entirely (fix #24).
- `test/Containerfile`: Rocky Linux 9 UBI-init base image; installs puppet-agent + haproxy; installs only stdlib, concat, firewall — **BUG**: missing vcsrepo and puppet-redis; copies only `modules/profile_haproxy` — **BUG**: missing profile_app_stack, profile_redis_cluster, base_utils, puppetdb_query_stub (fix #23).
- `test/site.pp`: Test node manifest including `profile_haproxy`, `profile_app_stack`, `profile_redis_cluster` — inconsistent with Containerfile which only ships one module.
- `test/hiera.yaml`: Single-level test hierarchy pointing to `test/data/common.yaml`; uses `%{module_name}` for module data lookup.
- `test/data/common.yaml`: Test overrides for all three profiles; sets `firewall_provider: none`; contains **plaintext passwords** (DB password, Redis auth password) — must be replaced with Ansible Vault secrets.
- `test/run.sh`: Podman-based test runner; applies manifest; verifies HAProxy config, backends, error pages, logrotate, service status.
- `site/profile/manifests/base/base.pp`: Base profile managing chrony (NTP), rsyslog, and base_utils via Hiera lookup; uses `$facts['kernel']` for OS branching.
- `site/profile/manifests/app/stack.pp`: Thin wrapper profile delegating to `profile_app_stack`; reads `fact('environment')` for app environment name.
- `site/profile/manifests/cache/redis.pp`: Thin wrapper profile delegating to `profile_redis_cluster`.
- `site/profile/manifests/loadbalancer/haproxy.pp`: Thin wrapper profile delegating to `profile_haproxy`.
- `site/role/manifests/app_stack.pp`: Role manifest composing `profile::base` + `profile::app::stack` with explicit ordering chain.
- `site/role/manifests/haproxy.pp`: Role manifest composing `profile::base` + `profile::loadbalancer::haproxy` with explicit ordering chain.
- `site/role/manifests/redis_cluster.pp`: Role manifest composing `profile::base` + `profile::cache::redis` with explicit ordering chain.

---

### Target Details

- **Operating System**: Dual-family targeting confirmed. Debian family: Ubuntu 22.04 and 24.04 (primary Vagrant/CI target). RedHat family: Rocky Linux 9 (container CI base, production target per `test/Containerfile` and `data/os/RedHat.yaml`). Package manager branching is present in `python.pp`, `database.pp`, and `os/` Hiera data files.
- **Virtual Machine Technology**: libvirt/KVM (Vagrantfile specifies `libvirt` provider with `generic/ubuntu2404` box). Container CI uses Podman with Rocky Linux 9 UBI-init image.
- **Cloud Platform**: Not specified. No cloud-provider SDK packages, metadata endpoint references, or cloud-init configurations detected. Infrastructure appears to be on-premises or private cloud.

---

## Migration Approach

### Key Dependencies to Address

- **puppetlabs-stdlib 9.7.0**: Provides `lookup()`, `fact()`, array/hash functions used throughout. Replace with Ansible built-in filters (`selectattr`, `combine`, `default`) and `vars` lookups. The `fact()` function calls in profile wrappers map directly to Ansible `ansible_facts`.
- **puppetlabs-concat 9.0.2**: Used for assembling HAProxy config fragments. Replace with Ansible `template` module (Jinja2) rendering the full `haproxy.cfg` in one pass — simpler than fragment assembly.
- **puppetlabs-firewall 8.1.3**: Manages iptables/nftables rules. Replace with `ansible.builtin.iptables`, `community.general.ufw`, or `ansible.posix.firewalld` depending on OS family. The existing `firewall_provider` Hiera key maps cleanly to an Ansible `when` condition.
- **puppetlabs-vcsrepo 6.1.0**: Git repository checkout for application code deployment. Replace with `ansible.builtin.git` module — direct 1:1 mapping for `ensure: latest`, `revision`, `provider: git`.
- **puppet-redis 11.0.0**: Redis installation and configuration. Replace with `community.general` Redis tasks or a dedicated role (e.g., `geerlingguy.redis`). The `redis.conf.erb` template maps directly to a Jinja2 template.
- **puppetlabs-apt 9.4.0**: APT repository management on Debian. Replace with `ansible.builtin.apt_repository` and `ansible.builtin.apt_key` modules.
- **hiera-eyaml**: Node-level secret encryption. Replace with **Ansible Vault** — encrypt individual variables or entire `host_vars/<node>/vault.yml` files. The five-tier Hiera hierarchy maps to Ansible's `group_vars/` + `host_vars/` directory structure.
- **puppetdb_query_stub / puppetdb_query()**: Dynamic peer discovery for Redis replication topology. Replace with Ansible **dynamic inventory** and group membership — nodes in the `redis_cluster` group are enumerated via `groups['redis_cluster']` in the replication task, eliminating the need for PuppetDB entirely.
- **Custom Facter fact `redis_role.rb`**: Detects primary vs. replica by reading `/etc/redis/conf.d/replica.conf`. Replace with an Ansible task that `stat`s the file and sets a `redis_role` variable, or use group membership (`redis_primary` / `redis_replica` inventory groups) as the source of truth.

---

### Security Considerations

- **eyaml-encrypted node secrets** (`hiera.yaml` nodes tier): The root Hiera hierarchy uses `hiera-eyaml` for per-node secrets (DB passwords, Redis auth tokens, SSL private key paths). Migration action: decrypt all eyaml values, re-encrypt with `ansible-vault encrypt_string` or store in per-host `host_vars/<node>/vault.yml` files encrypted with Ansible Vault. **Do not commit plaintext values at any point.**
- **Plaintext passwords in test data** (`test/data/common.yaml`): DB password and Redis auth password are stored in plaintext in the test Hiera data file. Migration action: replace with Ansible Vault-encrypted variables even in test/CI contexts; use a separate vault password file for CI pipelines.
- **`app.env.erb` template exposes DB_PASSWORD**: The application environment file template writes the database password as a plaintext environment variable in `/etc/app/<name>.env`. Migration action: use Ansible Vault for the variable; ensure the rendered file has mode `0600` and is owned by the application user (map from existing Puppet `owner`/`mode` resource attributes).
- **SSL/TLS certificate references** (`profile_haproxy`): HAProxy SSL is configured via a cert path parameter (`ssl_cert_path`). The actual certificate and private key are not managed in this repository — they are assumed to be pre-deployed (likely via a separate secrets management system). Migration action: document the certificate deployment dependency; consider `community.crypto` collection for cert management or integrate with HashiCorp Vault / AWS ACM.
- **HAProxy stats endpoint**: Stats are exposed on a configurable port (default 9000, node override 9001 for `lb01.fra.example.com`) with a password. The stats password appears in Hiera data. Migration action: migrate to Ansible Vault variable; ensure stats endpoint is firewall-restricted (already modelled in `firewall.pp` — map to `ansible.posix.firewalld` / `community.general.ufw` tasks).
- **Redis `requirepass`**: Redis authentication password is present in `test/data/common.yaml` in plaintext and referenced in `redis.conf.erb`. Migration action: Ansible Vault variable; ensure `redis.conf` is rendered with mode `0640`, owned by `redis:redis`.
- **Firewall management**: Two firewall providers are in use — `ufw` (Debian) and `firewalld` (RedHat). The `selinux_enabled: true` flag on RedHat targets means SELinux policy management is required for HAProxy (port binding, log socket access). Migration action: add `ansible.posix.selinux` and `community.general.seport` tasks for RedHat targets; map `policycoreutils-python-utils` package install to a RedHat-conditional task.
- **Credentials count by module**:
  - `profile_haproxy`: 2 credentials (stats password, SSL cert path reference)
  - `profile_app_stack`: 2 credentials (DB password in `app.env.erb`, app secret key)
  - `profile_redis_cluster`: 1 credential (Redis `requirepass`)
  - `base_utils` / `profile_base`: 0 credentials
  - `test/data/common.yaml`: 2 plaintext credentials (must be vaulted before migration)

---

### Technical Challenges

- **Dual module layout (`modules/` vs `site/modules/linux/`)**: The `environment.conf` modulepath gives `site/modules/linux/` precedence over `modules/`. Both directories contain copies of the same three modules with divergent bugs. Migration action: treat `site/modules/linux/` as the authoritative source; migrate from those copies only; archive `modules/` copies as reference. This must be decided and documented before migration begins to avoid migrating stale code.
- **Multi-tier Hiera hierarchy → Ansible group_vars/host_vars**: The five-tier hierarchy (node → environment → cluster → datacenter → common) with deep-merge semantics for backend server lists is the most complex structural mapping. Ansible's variable precedence is flatter. Migration action: model `cluster` and `datacenter` as Ansible inventory groups; use `group_vars/cluster_haproxy_prod_fra.yml`, `group_vars/datacenter_dc1_fra.yml`, etc. The `lookup_options: merge: deep` on `profile_haproxy::backends` must be replicated using Ansible's `combine` filter with `recursive=true` in the role's default variable assembly task.
- **PuppetDB dynamic peer discovery for Redis**: `profile_redis_cluster` uses `puppetdb_query()` to find peer nodes at catalog compile time. Ansible has no equivalent compile-time query. Migration action: use Ansible dynamic inventory (or static inventory groups `redis_primary`, `redis_replica`) and pass peer IPs as group variables. The `redis_role` custom fact logic must become an inventory group assignment or a pre-task that reads the replica config file.
- **`fact('environment')` vs Ansible environment**: Puppet's `$facts['agent_specified_environment']` (the Puppet environment — `production`, `staging`) is used to set the application's runtime `APP_ENV` variable in `app.env.erb`. In Ansible, there is no direct equivalent — the Puppet environment maps to an Ansible inventory group or an extra variable. Migration action: define `app_environment` as an explicit inventory group variable; do not rely on Ansible's `environment` keyword (which sets shell environment for tasks, not a node classification variable).
- **Custom Facter fact (`redis_role.rb`)**: This Ruby-based fact runs on the agent and returns `primary` or `replica` based on filesystem state. Ansible has no persistent custom facts mechanism by default. Migration action: either (a) use inventory groups as the source of truth for role assignment, or (b) use `ansible.builtin.stat` + `set_fact` at play runtime to detect the role from the filesystem (preserving the existing detection logic).
- **ERB templates → Jinja2**: All `.erb` templates use Ruby interpolation (`<%= @variable %>`, `<% if condition %>`). Migration action: convert to Jinja2 (`.j2`). Key differences: `@facts['networking']['fqdn']` → `ansible_fqdn`; `@params['key']` → role variable; `<% array.each do |item| %>` → `{% for item in list %}`. The `redis.conf.erb` and `haproxy.cfg.erb` templates are the most complex (100+ lines each).
- **Systemd service management**: `profile_app_stack` manages a Gunicorn systemd unit. The Puppet `service` resource maps to `ansible.builtin.systemd`. The unit file template must be converted from ERB to Jinja2. Ensure `daemon_reload: true` is set after unit file changes.
- **OS-conditional package names**: `python.pp` and `database.pp` have incomplete OS-conditional logic (confirmed bugs #14–17). Migration action: fix the Puppet bugs as part of pre-migration cleanup OR implement correctly in Ansible from the start using `ansible_os_family` conditionals and a `vars/` directory per OS family (`vars/Debian.yml`, `vars/RedHat.yml`).
- **logrotate integration**: Both `profile_haproxy` and `profile_app_stack` manage logrotate configurations. Replace with `community.general.logrotate` module or template-based `/etc/logrotate.d/<name>` file deployment.
- **Test infrastructure gaps (Containerfile + vagrant-provision.sh bugs)**: The existing CI is broken (confirmed bugs #23, #24). Migration action: fix these as part of the migration — the Ansible equivalent should use Molecule with a Docker/Podman driver, replacing both the Containerfile and Vagrantfile test approaches.
- **`puppetlabs-concat` fragment assembly**: HAProxy config is built from concat fragments in `profile_haproxy`. This pattern has no direct Ansible equivalent. Migration action: consolidate all fragment logic into a single Jinja2 template that iterates over the `backends` hash — this is actually simpler and more readable than the Puppet fragment approach.

---

### Migration Order

The following order minimises risk by starting with the lowest-complexity, highest-independence module and ending with the most interconnected:

1. **base_utils** (`site/modules/common/base_utils`) — Zero external Forge dependencies beyond stdlib; no secrets; pure package management. Ansible equivalent: a simple role with `ansible.builtin.package` and OS-family vars. Validates the group_vars/host_vars structure and OS-conditional pattern before tackling complex modules.

2. **profile_base** (`site/profile/manifests/base/base.pp` — chrony + rsyslog + base_utils) — Depends only on base_utils (migrated in step 1). Validates NTP and syslog configuration patterns. Ansible equivalent: tasks in a `base` role calling `ansible.builtin.template` for chrony.conf and rsyslog.conf, `ansible.builtin.service` for both daemons.

3. **profile_redis_cluster** (`site/modules/linux/profile_redis_cluster`) — Self-contained after resolving the PuppetDB query stub. Migrating this third forces resolution of the dynamic inventory strategy (replacing `puppetdb_query()`) before it becomes a blocker for the app stack. Ansible equivalent: `community.general` Redis tasks + Jinja2 `redis.conf.j2` template + inventory group-based replication topology.

4. **profile_app_stack** (`site/modules/linux/profile_app_stack`) — Depends on vcsrepo (→ `ansible.builtin.git`), PostgreSQL client libs, and systemd. Moderate complexity due to multi-manifest structure (install, database, python, monitoring, service, logrotate). Secrets (DB password) must be vaulted before this step. Ansible equivalent: multi-task role with `ansible.builtin.git`, `ansible.builtin.pip`, `ansible.builtin.template`, `ansible.builtin.systemd`.

5. **profile_haproxy** (`site/modules/linux/profile_haproxy`) — Most complex module: multi-tier Hiera data (cluster/datacenter/node overrides), deep-merge backend lists, dual firewall providers, SELinux policy, SSL, stats endpoint, logrotate. Migrate last to allow the Hiera→group_vars mapping pattern to be fully established by earlier migrations. Ansible equivalent: role with Jinja2 `haproxy.cfg.j2`, `ansible.posix.firewalld` / `community.general.ufw` tasks, `ansible.posix.selinux` + `community.general.seport` for RedHat, `community.general.logrotate`.

6. **Role composition** (`site/role/` manifests) — After all component roles are migrated, create Ansible playbooks that compose them: `site.yml` with plays targeting inventory groups (`haproxy_nodes`, `app_nodes`, `redis_nodes`), each play importing the base role plus the relevant component role. This replaces the Puppet role/profile pattern.

---

### Assumptions

1. **`site/modules/linux/` is the authoritative source**: Based on `environment.conf` modulepath ordering, the `site/modules/linux/` copies take precedence over `modules/`. It is assumed the `modules/` directory is a stale reference copy and migration will be based exclusively on `site/modules/linux/` content. This must be confirmed with the repository owners.

2. **No live PuppetDB in use**: The presence of `puppetdb_query_stub` in both `modules/` and the vagrant/test provisioning scripts strongly suggests PuppetDB is not operational in any tested environment. It is assumed Redis replication topology is either manually configured or not yet implemented. The Ansible migration will implement proper dynamic group-based topology from the start.

3. **eyaml private key is available**: The root `hiera.yaml` references eyaml for node-level secrets. It is assumed the eyaml private key is available to the migration team for decryption. If not, node-level secrets must be re-generated and rotated as part of migration.

4. **SSL certificates are externally managed**: No certificate issuance or renewal logic exists in this repository. It is assumed certificates are deployed out-of-band (manually, via a PKI system, or a separate automation layer). The Ansible migration will manage certificate *placement* (copying to the configured path) but not issuance.

5. **Puppet environment name maps to Ansible inventory group**: The Puppet `agent_specified_environment` variable (`production`, `staging`) is used as the application's `APP_ENV`. It is assumed this maps 1:1 to an Ansible inventory group name or an explicit `app_environment` host/group variable.

6. **`cluster` and `datacenter` Hiera facts are set as trusted facts or external facts**: The Hiera hierarchy uses `facts.cluster` and `facts.datacenter` for tier lookups. It is assumed these are set as Puppet trusted facts (in `csr_attributes.yaml`) or external facts. In Ansible, these will become inventory group memberships (`cluster_haproxy_prod_fra`, `datacenter_dc1_fra`).

7. **Rocky Linux 9 is the primary production OS**: The `test/Containerfile` uses Rocky Linux 9 UBI-init as its base, and `data/os/RedHat.yaml` is the most detailed OS-specific data file. It is assumed Rocky Linux 9 is the production target, with Ubuntu 24.04 used for development/Vagrant environments.

8. **libvirt/Vagrant is for developer workstations only**: The `Vagrantfile` is assumed to be a developer convenience tool, not a production provisioning mechanism. The Ansible migration will replace it with Molecule for role testing.

9. **The 25 confirmed Puppet bugs will be fixed before or during migration**: The migration plan assumes these bugs are addressed. If migration proceeds from the buggy source without fixes, the Ansible roles will inherit incorrect behaviour (wrong OS package names, deprecated fact references, broken CI). It is strongly recommended to fix bugs #1–22 in Puppet first, validate with the fixed CI (bugs #23–24), then migrate.

10. **`profile_app_stack` application name and repo URL are site-specific**: The `app_name` and `repo_url` parameters in `profile_app_stack` are not set to real values in any non-test Hiera data visible in this repository. It is assumed these are set in node-level eyaml data (not readable without the private key) or in an external node classifier. The Ansible migration will require these values to be explicitly documented in `host_vars` or `group_vars`.

11. **No Puppet Enterprise (PE) features in use**: No PE-specific resources (node classifier API, RBAC, orchestrator) are referenced. It is assumed this is an open-source Puppet installation, making the migration straightforward with no PE licensing considerations.

12. **`internal_monitoring` backend in `haproxy_prod_fra` cluster data**: This backend appears only in the Frankfurt production cluster Hiera data and has no corresponding application module in this repository. It is assumed it points to an external monitoring system (e.g., Prometheus, Zabbix) whose addresses are defined in the cluster data file. The Ansible migration must preserve this backend configuration.

13. **Test plaintext passwords are not used in production**: The passwords in `test/data/common.yaml` are assumed to be test-only values with no overlap with production credentials. Production credentials are assumed to be in eyaml-encrypted node data.

14. **`base_utils` package list is defined entirely in Hiera**: The `base_utils` module uses Hiera lookup for its package list with no hardcoded defaults visible. It is assumed the package list is defined in environment or common Hiera data not fully visible in this repository scan (possibly in eyaml node data or a common.yaml not shown).

15. **Molecule + Podman will replace the existing container CI**: The `test/run.sh` + `test/Containerfile` approach is assumed to be replaceable with Molecule scenarios. If the team has a strong preference for the existing Podman-based approach, the Ansible CI can be adapted, but Molecule is the recommended path.
