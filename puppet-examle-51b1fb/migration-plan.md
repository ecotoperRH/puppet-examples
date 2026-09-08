# MIGRATION FROM PUPPET TO ANSIBLE

## Executive Summary

This repository is a **Puppet 7/8 control repository** implementing a Roles & Profiles pattern for a three-tier web application platform. It manages a Python/FastAPI application stack, an HAProxy load balancer, and a Redis cluster, all deployed on Ubuntu 24.04 (primary) with secondary support for RedHat 8/9 and Debian 11/12.

The repository contains **4 custom Puppet modules** (with two sets of near-duplicate copies across `modules/` and `site/modules/linux/`), **1 utility module** (`base_utils`), **1 stub module** (`puppetdb_query_stub`), a thin **Roles & Profiles** layer, and a multi-level Hiera data hierarchy (up to 21 levels in `profile_haproxy`). The most significant migration challenges are:

1. **PuppetDB-driven dynamic node discovery** used by both `profile_haproxy` and `profile_redis_cluster` — this has no direct Ansible equivalent and requires an architectural redesign using Ansible inventory or a service-discovery mechanism.
2. **eyaml (PKCS7) encrypted secrets** throughout the Hiera data hierarchy — these must be re-encrypted and migrated to Ansible Vault.
3. **Deep Hiera hierarchy** (21 levels in `profile_haproxy`) encoding environment, datacenter, cluster, and per-node overrides — this must be flattened into Ansible group/host variables.
4. **Custom Puppet functions and Facter facts** (Ruby) that have no Ansible equivalent and must be re-implemented as Jinja2 filters, `set_fact` tasks, or custom modules.

**Estimated migration effort:** 8–12 weeks for a small platform team (2–3 engineers), assuming parallel development and a phased cutover strategy.

---

## Module Migration Plan

This repository contains Puppet modules, profiles, and roles that need individual migration planning.

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
All paths below were confirmed from the provided repository tree and file reads. The `modules/` and `site/modules/linux/` directories contain near-identical copies of the three core profile modules; both sets are listed because they differ in OS support scope and, in the case of `profile_haproxy`, in manifest content (the `site/modules/linux/` version adds a `discover.pp` subclass).

---

- **profile_app_stack** *(modules/ copy)*:
    - Description: Full Python/FastAPI application stack orchestrator. Manages Python runtime installation (configurable version, venv), system user/group creation, Git repository cloning via `vcsrepo`, pip dependency installation, `.env` file generation from an ERB template, PostgreSQL provisioning (local or remote), Alembic database migrations, systemd service unit deployment from an EPP template, logrotate configuration, and Prometheus monitoring resources (node-exporter + pushgateway, realized only in production). Implements a strict five-phase dependency chain: `python → database → app → service → monitoring`.
    - Path: `modules/profile_app_stack`
    - Technology: Puppet
    - Key Features: Gunicorn/Uvicorn worker configuration, eyaml-encrypted `db_password` and `secret_key`, Alembic migration execution, environment-conditional `DEBUG`/`CORS_ORIGINS` in `.env`, production-only Prometheus virtual resources, cron-based DB backup and health-check scheduling, logrotate management.

- **profile_haproxy** *(modules/ copy)*:
    - Description: HAProxy load balancer profile with static Hiera-driven backend configuration. Installs HAProxy and optional OS packages (e.g., `hatop`), manages the `haproxy` user/group, renders `haproxy.cfg` from an ERB template, generates per-backend config fragments in `conf.d/` via a Hiera hash loop, deploys custom 408/503 error pages, manages UFW firewall rules (ports 80, 443, stats port), and controls the HAProxy service. SSL/TLS termination is environment-conditional (disabled in staging, enabled in production with TLSv1.2+ minimum). Stick-table session persistence is production-only.
    - Path: `modules/profile_haproxy`
    - Technology: Puppet
    - Key Features: 21-level Hiera hierarchy for parameter resolution, deep-merge backend hash across node/cluster/datacenter/environment layers, eyaml-encrypted `stats_password`, UFW firewall management, per-datacenter backend server overrides (Frankfurt DC), SSL cipher suite configuration.

- **profile_redis_cluster** *(modules/ copy)*:
    - Description: Redis standalone/cluster node profile. Delegates installation and configuration to the upstream `puppet-redis` Forge module. Configures bind address, port, `requirepass` password, `maxmemory` limit, `allkeys-lru` eviction policy, and AOF persistence. Uses a `puppetdb_query` call to discover all cluster peer nodes at catalog compile time (currently returns an empty array via the stub when PuppetDB is unavailable).
    - Path: `modules/profile_redis_cluster`
    - Technology: Puppet
    - Key Features: PuppetDB-based peer discovery, hardcoded default password (`CHANGEME`) requiring override, AOF + RDB persistence, `redis_role` custom Facter fact (primary vs. replica detection via `/etc/redis/conf.d/replica.conf`).

- **puppetdb_query_stub**:
    - Description: A test/development stub that replaces the `puppetdb_query` Puppet function with a no-op implementation returning an empty array. Used during local Vagrant and container-based testing when no live PuppetDB server is available. Emits a Puppet warning when invoked.
    - Path: `modules/puppetdb_query_stub`
    - Technology: Puppet (Ruby function stub)
    - Key Features: Allows catalog compilation without a PuppetDB connection; must not be deployed to production. Has no Ansible equivalent — the migration must replace the underlying PuppetDB queries with Ansible inventory groups or dynamic inventory scripts.

- **profile_app_stack** *(site/modules/linux/ copy)*:
    - Description: Functionally identical to the `modules/profile_app_stack` copy but with expanded OS support (RedHat 8/9 + Ubuntu 22.04/24.04 vs. Ubuntu 24.04 only). Loaded first in the `modulepath` (`site/modules/linux:…:modules`), so it takes precedence on Linux nodes. Contains the same subclasses, templates, and Hiera data files.
    - Path: `site/modules/linux/profile_app_stack`
    - Technology: Puppet
    - Key Features: Same as `modules/profile_app_stack`; broader OS matrix. The duplication between this and the `modules/` copy is a technical debt item that should be resolved (merged) before or during migration.

- **profile_haproxy** *(site/modules/linux/ copy)*:
    - Description: Extended version of the `modules/profile_haproxy` copy. Adds a `profile_haproxy::discover` subclass that uses PuppetDB exported resources (`@@haproxy::balancermember`) and a `puppetdb_query` call to dynamically populate HAProxy backends from live application server nodes. Also expands OS support to include RedHat 8/9 and Debian 11/12. This copy is loaded first in the `modulepath` and therefore takes precedence.
    - Path: `site/modules/linux/profile_haproxy`
    - Technology: Puppet
    - Key Features: PuppetDB exported resource collection for dynamic backend registration, `puppetdb_query` for environment-scoped app server discovery, `Sensitive[String]` type wrapping for `stats_password`, broader OS matrix than the `modules/` copy.

- **profile_redis_cluster** *(site/modules/linux/ copy)*:
    - Description: Functionally identical to `modules/profile_redis_cluster` but with expanded OS support (RedHat 8/9 + Ubuntu 22.04/24.04). Loaded first in the `modulepath`. Contains its own `Puppetfile` pinning `puppet-redis 11.0.0` and `puppetlabs-apt 9.4.0`.
    - Path: `site/modules/linux/profile_redis_cluster`
    - Technology: Puppet
    - Key Features: Same as `modules/profile_redis_cluster`; broader OS matrix.

- **base_utils**:
    - Description: Common base utility module included by all roles via `profile::base::base`. Manages the `/etc/motd` file from an ERB template, installs a configurable list of OS-specific utility packages (e.g., `vim-enhanced`, `wget`, `curl`, `jq`, `bind-utils` on RedHat; empty list on Debian by default), and provides reusable defined types (`config_entry`, `create_dir`, `managed_notify`), custom types (`ensure_value`, `log_level`, `port`), and Puppet Bolt plans/tasks (`rolling_restart` plan, `check_service` task). Supports RedHat 8/9, Debian 11/12, and Ubuntu 22.04/24.04.
    - Path: `site/modules/common/base_utils`
    - Technology: Puppet
    - Key Features: OS-family-aware package lists via Hiera, `base_utils::config_entry` defined type (key=value file line management using `file_line`), Bolt `rolling_restart` plan with per-node service health verification and configurable inter-node delay, `check_service` Bolt task (systemd status check returning JSON), custom `platform_info` external fact.

---

### Infrastructure Files

- `Puppetfile`: Root-level Forge module pin file. Declares all external module dependencies: `puppetlabs-stdlib 9.7.0`, `puppetlabs-concat 9.0.2`, `puppetlabs-firewall 8.1.3`, `puppetlabs-vcsrepo 6.1.0`, `puppet-redis 11.0.0`, `puppetlabs-apt 9.4.0`. Migration consideration: each Forge module must be replaced with an equivalent Ansible collection or role (see Key Dependencies).
- `environment.conf`: Defines the Puppet `modulepath` as `site/modules/linux:site/modules/common:site:modules:$basemodulepath`. The `site/modules/linux` path takes precedence, explaining why the `site/` copies of the three profile modules shadow the `modules/` copies. In Ansible, this layering must be replicated via role search paths or explicit role dependencies.
- `hiera.yaml`: Root environment Hiera configuration (Hiera 5). Defines a 3-level hierarchy: per-node eyaml (PKCS7-encrypted), per-environment YAML, and common YAML. The eyaml private key path (`/etc/puppetlabs/puppet/eyaml/private_key.pkcs7.pem`) is a critical secret management dependency.
- `data/common.yaml`: Environment-wide defaults for NTP servers, SSH hardening parameters (`client_alive_interval: 300`, `permit_root_login: false`), and syslog server/facility. References `ntp`, `ssh`, and `syslog` classes not present as modules in this repo — likely managed by external Forge modules or a separate control repo.
- `data/environment/production.yaml`: Production overrides for NTP (internal servers) and syslog (internal syslog aggregator). Migration consideration: map to Ansible `group_vars/production/`.
- `data/environment/staging.yaml`: Staging overrides for NTP and syslog. Map to Ansible `group_vars/staging/`.
- `Vagrantfile`: Local development environment using `bento/ubuntu-24.04` on libvirt (2 vCPU, 2 GB RAM). Provisions via `vagrant-provision.sh`. Useful as a reference for the target Ansible development/test environment.
- `vagrant-provision.sh`: Shell provisioner that installs Puppet 8 agent, installs Forge modules, copies module directories, and runs `puppet apply`. Reveals the exact module versions in use and the test topology. The container test (`test/Containerfile`) uses Rocky Linux 9 (UBI init), confirming RedHat family support is a real requirement.
- `test/Containerfile`: OCI container image based on `rockylinux/rockylinux:9-ubi-init` for CI testing of `profile_haproxy`. Confirms Rocky Linux 9 / RHEL 9 as a supported target platform.
- `test/site.pp`: Integration test manifest. Applies all three profiles to a single `node default`, with a test Git repository fixture for the app stack. Useful as a reference for Ansible integration test playbooks.
- `test/hiera.yaml` / `test/data/common.yaml`: Minimal Hiera configuration for test runs. Provides baseline values without eyaml encryption.

---

### Target Details

- **Operating System**: Ubuntu 24.04 LTS (primary, confirmed by `Vagrantfile` box and `modules/` metadata). Secondary targets: RedHat Enterprise Linux 8 & 9 / Rocky Linux 9 (confirmed by `test/Containerfile` and `site/modules/linux/` metadata), Debian 11 & 12, Ubuntu 22.04. The `profile_haproxy` OS-specific Hiera data (`data/os/Debian.yaml`) and `base_utils` OS data (`data/os/RedHat.yaml`) confirm active multi-OS usage.
- **Virtual Machine Technology**: libvirt/KVM (confirmed by `Vagrantfile` `config.vm.provider "libvirt"` block). No cloud-specific tooling detected.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP SDK references found in any reviewed file.

---

## Migration Approach

### Key Dependencies to Address

- **puppetlabs-stdlib 9.7.0**: Provides `file_line`, `stdlib` functions, and data types used pervasively across all modules. Replace with native Ansible `lineinfile` module for `file_line` usage; most stdlib functions have direct Jinja2/Ansible equivalents (`any`, `all`, `flatten`, `merge`, etc.).
- **puppetlabs-vcsrepo 6.1.0**: Used by `profile_app_stack` to clone the application Git repository. Replace with `ansible.builtin.git` module — a direct functional equivalent supporting `repo`, `dest`, `version`, `force`, and `update` parameters.
- **puppet-redis 11.0.0**: Wraps Redis installation and configuration. Replace with the `community.general` collection or a dedicated Redis Ansible role (e.g., `geerlingguy.redis` from Ansible Galaxy). The `redis.conf.erb` template can be ported directly to a Jinja2 template.
- **puppetlabs-concat 9.0.2**: Used by `profile_haproxy` to assemble configuration fragments. Replace with Ansible `template` + `assemble` modules, or generate the full `haproxy.cfg` from a single Jinja2 template with loops over the backends dictionary — the cleaner approach given the data is already a Hiera hash.
- **puppetlabs-firewall 8.1.3**: Declared as a dependency of `profile_haproxy` but the actual firewall management in the reviewed manifests uses raw `exec` calls to `ufw`. Replace with `community.general.ufw` Ansible module for UFW rules, or `ansible.posix.firewalld` for RHEL targets.
- **puppetlabs-apt 9.4.0**: APT repository management for Debian/Ubuntu targets. Replace with `ansible.builtin.apt_repository` and `ansible.builtin.apt_key` modules.
- **eyaml (hiera-eyaml / PKCS7)**: Encrypts secrets in Hiera YAML files. Replace with **Ansible Vault** (`ansible-vault encrypt_string` for inline secrets or vault files). The PKCS7 private key must be available during migration to decrypt existing values.
- **PuppetDB + exported resources**: Used by `profile_haproxy::discover` (exported `haproxy::balancermember` resources) and `profile_redis_cluster` (peer node discovery). Replace with **Ansible dynamic inventory** (static group membership, cloud inventory plugins, or a service-discovery tool such as Consul). For HAProxy backends, the Hiera-static approach already present in `data/common.yaml` is the simpler migration path and should be preferred initially.

---

### Security Considerations

- **eyaml PKCS7 encrypted secrets**: Multiple secrets are encrypted with eyaml across the Hiera hierarchy. Identified encrypted values:
  - `profile_app_stack::db_password` — PostgreSQL application user password (`modules/profile_app_stack/data/common.yaml`)
  - `profile_app_stack::secret_key` — Application `SECRET_KEY` environment variable, production value (`modules/profile_app_stack/data/environment/production.yaml`); staging uses a plaintext value (`staging-not-secret-at-all`), which is a security finding.
  - `profile_haproxy::stats_password` — HAProxy statistics page password (`modules/profile_haproxy/data/common.yaml`)
  - All three must be decrypted using the PKCS7 private key and re-encrypted with Ansible Vault before migration. The PKCS7 private key itself must be securely transferred and then destroyed.
- **Hardcoded default credentials**: `profile_redis_cluster` defaults `redis_password` to the literal string `'CHANGEME'` in `manifests/init.pp`. This default must be eliminated; the Ansible equivalent must require the variable to be explicitly set (e.g., using `vars_prompt` or a mandatory vault variable with no default).
- **Staging plaintext secret**: `profile_app_stack::secret_key: staging-not-secret-at-all` in `modules/profile_app_stack/data/environment/staging.yaml` is a plaintext secret. While staging environments often have relaxed security, this value should still be managed via Ansible Vault to establish consistent secret hygiene.
- **SSL/TLS certificate management**: `profile_haproxy` references `ssl_cert_path` and `ssl_key_path` parameters (defaulting to `/etc/ssl/certs` and `/etc/ssl/private`). The certificates themselves are not managed in this repository. The Ansible migration must include a certificate deployment task (e.g., using `ansible.builtin.copy` with vault-encrypted content, or integration with a secrets manager such as HashiCorp Vault or AWS Secrets Manager).
- **`.env` file permissions**: The application `.env` file (containing `DATABASE_URL` and `SECRET_KEY`) is deployed with mode `0600` owned by the app user. This must be preserved in the Ansible `template` task (`mode: '0600'`).
- **HAProxy config file permissions**: `haproxy.cfg` and backend fragments are deployed with mode `0640` (root:haproxy). Preserve in Ansible `template` tasks.
- **SSH hardening parameters**: `data/common.yaml` references `ssh::permit_root_login: false` and `ssh::client_alive_interval: 300`. These are managed by an external `ssh` class not present in this repo. Ensure equivalent `ansible.builtin.lineinfile` or `template` tasks for `/etc/ssh/sshd_config` are included in the base role.
- **Puppet eyaml private key**: Located at `/etc/puppetlabs/puppet/eyaml/private_key.pkcs7.pem` on the Puppet master. This key must be securely retrieved to decrypt existing secrets during migration and must not be committed to the Ansible repository.

---

### Technical Challenges

- **PuppetDB dynamic node discovery (High Complexity)**: Both `profile_haproxy::discover` and `profile_redis_cluster` use `puppetdb_query` to discover peer nodes at catalog compile time. Ansible has no equivalent compile-time node query mechanism. Mitigation: (1) For HAProxy, the static Hiera backend hash approach already present in `data/common.yaml` is a viable replacement — populate `group_vars` with backend server lists managed by the inventory. (2) For Redis cluster peer discovery, use Ansible's `groups['redis_cluster']` inventory group variable in the Jinja2 template. (3) For the dynamic `discover.pp` exported-resource pattern, consider a service registry (Consul, etcd) or accept static inventory management as the operational model.
- **21-level Hiera hierarchy flattening (High Complexity)**: `profile_haproxy`'s `hiera.yaml` defines 21 lookup levels (node, role, cluster, application tier, application, team, business unit, lifecycle, environment, network zone, datacenter, region, country, CPU architecture, OS release, OS family+release, OS name, OS family, kernel, container detection, virtual/physical, common). Only a subset of these levels have actual data files in the repository, but the full hierarchy implies a complex variable precedence model. Mitigation: Audit which hierarchy levels have populated data files, map them to Ansible `group_vars/` and `host_vars/` directories, and document the precedence rules explicitly. Levels with no data files can be dropped.
- **Module duplication (`modules/` vs `site/modules/linux/`)**: Three modules exist in near-identical copies in two locations, with `site/modules/linux/` taking precedence via `modulepath`. The `site/modules/linux/profile_haproxy` copy adds `discover.pp` and a `Sensitive[String]` type for `stats_password`. Mitigation: Consolidate into a single Ansible role per logical module before migration; do not create two Ansible roles for the same function.
- **Custom Puppet functions (Ruby)**: `profile_app_stack::app_db_url` (builds a PostgreSQL connection URL with URL-encoded password) and the `puppetdb_query` stub are Ruby functions with no Ansible equivalent. Mitigation: Replace `app_db_url` with a Jinja2 expression in the `.env` template (e.g., `DATABASE_URL: "postgresql://{{ db_user }}:{{ db_password | urlencode }}@{{ db_host }}:{{ db_port }}/{{ db_name }}"`). The `puppetdb_query` function is replaced by inventory-based approaches as described above.
- **Custom Facter facts (Ruby)**: `redis_role` (detects primary vs. replica by inspecting `/etc/redis/conf.d/replica.conf`) and `haproxy_version` (parses `haproxy -v` output) are custom Ruby facts. Mitigation: Replace with Ansible `set_fact` tasks using `ansible.builtin.stat` and `ansible.builtin.command` with `register`, or use `ansible_facts` gathered by the `setup` module where applicable.
- **Puppet virtual resources**: `profile_app_stack::monitoring` uses virtual resources (`@package`, `@service`, `@cron`) that are only realized in production via `if $facts['environment'] == 'production'`. Mitigation: Replace with Ansible `when: ansible_environment == 'production'` conditionals on the relevant tasks. This is straightforward but requires careful mapping of the `environment` fact to an Ansible variable.
- **Alembic database migrations**: `profile_app_stack::app` runs `alembic upgrade head` as a `refreshonly` exec triggered by `vcsrepo` changes. Ansible has no native `refreshonly` equivalent. Mitigation: Use `ansible.builtin.command` with a `changed_when` condition tied to the Git checkout task's `register` result, or use a dedicated migration handler.
- **Bolt plans and tasks**: `base_utils` includes a `rolling_restart` Bolt plan and a `check_service` Bolt task. These are operational runbooks, not configuration management. Mitigation: Port `rolling_restart` to an Ansible playbook with `serial: 1` and a `wait_for` or `uri` health check between hosts. Port `check_service` to an ad-hoc `ansible.builtin.systemd` status check.
- **`exec` resource idempotency**: Several `exec` resources in `profile_app_stack::database` use shell `unless` guards for idempotency (e.g., checking `pg_roles` before creating a DB user). Ansible's `community.postgresql` collection (`postgresql_user`, `postgresql_db`) provides native idempotent equivalents and should be used instead of raw `command` tasks.

---

### Migration Order

The following order minimizes risk by starting with the lowest-complexity, highest-independence module and ending with the most complex:

1. **`base_utils`** — No external Forge dependencies beyond `stdlib`. Manages MOTD, utility packages, and provides helper types/tasks. Low risk, high value as a foundation for all other roles. Port to an Ansible `base` role with OS-conditional package lists in `group_vars`. Port Bolt tasks to Ansible ad-hoc commands/playbooks.

2. **`profile_redis_cluster`** — Depends only on `puppet-redis` (well-understood, direct Ansible equivalent available). PuppetDB peer discovery returns an empty array in the current stub, so the static configuration path is already the effective behavior. Port to an Ansible role using `community.general` or `geerlingguy.redis`. Migrate `redis_password` to Ansible Vault. Resolve the `CHANGEME` default credential.

3. **`profile_app_stack`** — Moderate complexity. No PuppetDB dependency. Requires porting: Python/venv setup, Git clone (`ansible.builtin.git`), pip install, `.env` template (Jinja2), systemd unit template (Jinja2), PostgreSQL provisioning (`community.postgresql.*`), Alembic migration handler, logrotate template, and Prometheus monitoring tasks with environment conditionals. Migrate `db_password` and `secret_key` to Ansible Vault.

4. **`profile_haproxy`** — Highest complexity. Requires: resolving the 21-level Hiera hierarchy into `group_vars`/`host_vars`, porting the backends hash loop to a Jinja2 template loop, replacing PuppetDB exported resources with static inventory groups, porting UFW firewall rules (`community.general.ufw`), and migrating `stats_password` to Ansible Vault. Tackle the static Hiera-driven configuration path first, then address dynamic backend discovery as a follow-on.

5. **Roles & Profiles layer** (`site/role/`, `site/profile/`)  — Thin wrappers; port last as Ansible playbooks that `import_role` the migrated roles in the correct order, replicating the `Class['base'] -> Class['app_stack']` dependency chains as task ordering within plays.

---

### Assumptions

1. **Active Puppet infrastructure**: It is assumed a live Puppet master with PuppetDB is in use in production. The `puppetdb_query_stub` module and its warning message suggest PuppetDB queries are real production dependencies, not just theoretical.
2. **eyaml private key availability**: It is assumed the PKCS7 private key (`/etc/puppetlabs/puppet/eyaml/private_key.pkcs7.pem`) is accessible to the migration team for decrypting existing secrets. If the key has been rotated or is unavailable, secrets must be reset rather than migrated.
3. **Module duplication is intentional layering**: The presence of near-identical modules in both `modules/` and `site/modules/linux/` appears to be an intentional `modulepath` layering pattern (Linux-specific overrides shadow generic versions). This is treated as a single logical module per function for Ansible migration purposes.
4. **`ntp`, `ssh`, and `syslog` classes are out of scope**: `data/common.yaml` references `ntp::servers`, `ssh::permit_root_login`, and `syslog::server` parameters, but no corresponding modules exist in this repository. These are assumed to be managed by external Forge modules or a separate control repo and are out of scope for this migration unless explicitly included.
5. **Frankfurt datacenter is the only active datacenter**: Only `dc1_fra` datacenter data and `lb01.fra.example.com` node data exist in the Hiera hierarchy. Other datacenter/region/country hierarchy levels defined in `profile_haproxy`'s `hiera.yaml` are assumed to be unpopulated placeholders.
6. **Static backend configuration is acceptable for initial migration**: The `profile_haproxy::discover` PuppetDB-based dynamic backend registration is a significant architectural dependency. It is assumed the team is willing to accept statically-defined inventory groups as the initial Ansible equivalent, with dynamic service discovery as a future enhancement.
7. **Vagrant/libvirt is the development environment**: No cloud provider is detected. It is assumed the team uses local libvirt VMs for development and testing. The Ansible development environment should mirror this setup (e.g., using `vagrant` with the `ansible` provisioner or Molecule with a libvirt driver).
8. **Rocky Linux 9 is the RHEL-family target**: The `test/Containerfile` uses `rockylinux/rockylinux:9-ubi-init`. It is assumed Rocky Linux 9 (or an equivalent RHEL 9 derivative) is the target for RedHat-family deployments, not CentOS or Oracle Linux.
9. **`profile_app_stack` deploys a single application**: The module is parameterized for a single app (`myapp-api`). It is assumed only one application instance is deployed per node. Multi-tenancy (multiple apps per host) is out of scope.
10. **Alembic migrations are safe to run on every deployment**: The `refreshonly` guard in Puppet means migrations only run when the Git repo changes. In Ansible, this behavior must be explicitly replicated; it is assumed the team will validate migration idempotency before enabling automatic migration execution in CI/CD pipelines.
11. **The `profile_haproxy` 21-level hierarchy is partially populated**: Only `nodes/`, `cluster/`, `datacenter/`, `environment/`, and `os/` data directories exist under `modules/profile_haproxy/data/`. The remaining 16 hierarchy levels (role, application tier, team, business unit, etc.) are assumed to be defined for future use and have no current data, so they can be omitted from the initial Ansible variable structure.
