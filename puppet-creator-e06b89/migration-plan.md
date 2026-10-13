# MIGRATION FROM PUPPET TO ANSIBLE

This repository is a Puppet 7/8 control repository with Hiera 5 data, custom Puppet/Facter functions, PuppetDB discovery, Bolt plans/tasks, and Linux service profiles. The functional estate is small in module count but moderate in migration complexity because the same application, HAProxy, and Redis profiles exist in both `modules/` and `site/modules/linux/`, with possible behavioral drift between copies. The target migration should preserve role composition, ordered convergence, environment-specific data, encrypted secrets, service lifecycle behavior, and operational checks. A realistic initial migration is approximately 6–10 weeks for one experienced Ansible engineer plus application/platform reviewers; parallel work can reduce elapsed time, but validation and cutover should remain staged.

## Module Migration Plan

This repository contains Puppet modules, site profiles, roles, Hiera data, and Puppet operational extensions that need individual migration planning.

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
The following paths are present in the supplied repository tree. The repository tree explicitly shows six module directories with `manifests/init.pp`; `puppetdb_query_stub` has no `init.pp` and is treated as a custom extension rather than a deployable Puppet module.

- **profile_app_stack (root copy)**:
    - Description: Python application stack profile that installs/configures a Python application from Git, creates a virtual environment, installs pip dependencies, optionally provisions local PostgreSQL, runs Alembic migrations, installs a systemd service, deploys environment and health-check files, and schedules database backups.
    - Path: `modules/profile_app_stack`
    - Technology: Puppet
    - Key Features: Strict Python → database → application → service → monitoring ordering; PostgreSQL 15? version is not pinned; Git deployment through `vcsrepo`; systemd and cron; custom database URL function; encrypted Hiera database password.

- **profile_haproxy (root copy)**:
    - Description: HAProxy load-balancer profile that installs HAProxy, creates its service account and directories, renders configuration from hierarchical backend data, manages service ordering, and configures an Ubuntu UFW firewall.
    - Path: `modules/profile_haproxy`
    - Technology: Puppet
    - Key Features: Multi-backend routing, health checks, stats endpoint, SSL parameters, custom error pages, firewall rules, HAProxy version facter function, and deep Hiera backend merging.

- **profile_redis_cluster (root copy)**:
    - Description: Redis server profile that configures Redis through the `puppet-redis` module and attempts to discover cluster peers through a PuppetDB query.
    - Path: `modules/profile_redis_cluster`
    - Technology: Puppet
    - Key Features: Password authentication, persistence (`appendonly`/`everysec`), memory limit and eviction policy, bind address, and PuppetDB-based node discovery.

- **base_utils**:
    - Description: Common Linux/Unix utility module providing MOTD management, configurable utility package installation, custom types/functions, Facter metadata, and Bolt operational actions.
    - Path: `site/modules/common/base_utils`
    - Technology: Puppet with Bolt plans/tasks
    - Key Features: `/etc/motd` management, helper defined types and validation types, health-check task/plan, rolling restart plan, OS-specific Hiera data, and a facts.d platform descriptor.

- **profile_app_stack (site Linux copy)**:
    - Description: Linux application-stack profile with the same broad Python/PostgreSQL/systemd purpose as the root copy, but with expanded OS metadata for Red Hat and Debian families.
    - Path: `site/modules/linux/profile_app_stack`
    - Technology: Puppet
    - Key Features: Application Git checkout, virtualenv and pip installation, local PostgreSQL conditional on `db_host`, database backup cron, environment file, systemd service, health check, and migration trigger.

- **profile_haproxy (site Linux copy)**:
    - Description: Linux HAProxy load-balancer profile with installation, configuration, service, discovery, and firewall phases.
    - Path: `site/modules/linux/profile_haproxy`
    - Technology: Puppet
    - Key Features: Multi-level HAProxy data, production Frankfurt cluster data, backend health checks, SSL configuration, UFW rules, and an additional `discover` phase not present in the root copy.

- **profile_redis_cluster (site Linux copy)**:
    - Description: Linux Redis profile using the Puppet Redis module, with the same Redis settings and PuppetDB-oriented cluster intent as the root copy.
    - Path: `site/modules/linux/profile_redis_cluster`
    - Technology: Puppet
    - Key Features: Redis package/configuration management, authentication, AOF persistence, maxmemory policy, and custom Redis role facter support.

The site-level composition layer is not a separate module inventory item, but must be migrated as part of the design:

- `site/profile/manifests/base/base.pp`: common role profile for utility packages, chrony, and rsyslog.
- `site/profile/manifests/app/stack.pp`: wrapper for the application profile.
- `site/profile/manifests/cache/redis.pp`: wrapper for the Redis profile.
- `site/profile/manifests/loadbalancer/haproxy.pp`: wrapper for the HAProxy profile.
- `site/role/manifests/app_stack.pp`, `haproxy.pp`, and `redis_cluster.pp`: node roles that include the base profile and enforce base-before-service ordering.

### Infrastructure Files

- `Puppetfile`: Root Forge dependency lock intent. Declares `puppetlabs-stdlib 9.7.0`, `puppetlabs-concat 9.0.2`, `puppetlabs-firewall 8.1.3`, `puppetlabs-vcsrepo 6.1.0`, `puppet-redis 11.0.0`, and `puppetlabs-apt 9.4.0`. Replace with Ansible collection requirements and explicit package/version policy.
- `environment.conf`: Defines the effective Puppet module path: `site/modules/linux:site/modules/common:site:modules:$basemodulepath`. This explains precedence and the duplicate profile copies; it must be replaced by explicit Ansible role/collection layout.
- `hiera.yaml`: Hiera 5 hierarchy with encrypted per-node data, per-environment data, and common data. Its lookup/precedence model must be translated into inventory/group/host variables and Ansible Vault.
- `data/`, module `data/`, and site module data directories: Environment, OS, datacenter, cluster, node, and common configuration sources. These are the primary inputs for variable extraction and precedence testing.
- `site/profile` and `site/role`: Puppet composition layer. Convert profiles to roles/tasks and roles to inventory groups or playbook entry points.
- `modules/*/templates`, `site/modules/*/templates`: ERB/EPP templates for application environment/systemd/logrotate, HAProxy configuration/backend fragments, and Redis configuration. Convert to Jinja2 templates, preserving file ownership/mode and handler behavior.
- `modules/*/files` and site equivalents: Backup and health-check scripts, HAProxy error pages, and static operational assets. Copy into role `files/` and review shell scripts for idempotence and secret handling.
- `modules/profile_redis_cluster/Puppetfile` and `site/modules/linux/profile_haproxy/Puppetfile`: Module-local dependency declarations that must be reconciled with the root Puppetfile before migration.
- `lib/puppet`, `lib/facter`, `modules/puppetdb_query_stub`: Custom Ruby extension points. Replace the application DB URL helper with normal Ansible variable composition, replace facts with gathered facts/custom facts only where required, and replace PuppetDB discovery with inventory, service discovery, or an external dynamic inventory mechanism.
- `test/Containerfile`, `test/site.pp`, `test/hiera.yaml`, `test/data`, and `test/run.sh`: Container-based Puppet validation harness. Rebuild as Molecule/testcontainers or Ansible container integration tests.
- `Vagrantfile` and `vagrant-provision.sh`: Ubuntu 24.04/libvirt development VM with private networking and forwarded HTTP/HTTPS ports. Retain as an optional Ansible development target or replace with Molecule/libvirt.

### Target Details

- **Operating System**: Primarily Ubuntu 24.04, explicitly supported by the root application/HAProxy/Redis metadata and used by the Vagrant box. The site modules additionally claim Red Hat Enterprise Linux 8/9 and Debian 11/12 support. The supplied container test uses Rocky Linux 9 UBI, so the Ansible implementation must deliberately test both Debian-family and Red Hat-family package/service/firewall behavior rather than assuming Ubuntu.
- **Virtual Machine Technology**: libvirt via Vagrant is explicitly used (`config.vm.provider "libvirt"`). No production hypervisor is specified.
- **Cloud Platform**: Not specified. Backend addresses are private IPs and the configuration contains no AWS, Azure, or GCP integration.

## Migration Approach

### Key Dependencies to Address

- **puppetlabs-stdlib 9.6/9.7**: Replace Puppet helper behavior with Ansible built-in filters, `ansible.builtin` modules, and role defaults/vars. Avoid translating implementation details that are not required by the target state.
- **puppetlabs-concat 9.0.2**: Replace concatenated HAProxy fragments with a single Jinja2 template or deterministic `template` plus validation handler.
- **puppetlabs-firewall 8.1.3**: Implement firewall policy with `community.general.ufw` on Ubuntu and an explicit `ansible.posix.firewalld`/nftables strategy for RHEL-family hosts. Preserve source restrictions and do not expose the stats port broadly by default.
- **puppetlabs-vcsrepo 6.1.0**: Use `ansible.builtin.git` with pinned revision, repository credentials supplied through Vault/SSH deploy keys, and a handler for application restart.
- **puppet-redis 11.0.0**: Replace with an Ansible Redis role or a maintained collection, or implement a small internal role for package, config, service, persistence, and password settings. Confirm Redis version and cluster semantics before selecting a role.
- **puppetlabs-apt 9.4.0**: Use `ansible.builtin.apt_repository`, `apt`, and equivalent `dnf` modules only if repository management is actually required; current reviewed entrypoints do not establish a complete repository policy.
- **PostgreSQL and Python runtime**: Use distribution package modules plus `community.postgresql` for users/databases/privileges, `ansible.builtin.pip` or a reproducible virtualenv workflow, and explicit package/version pinning. Do not retain shell `psql` commands as the primary implementation.
- **PuppetDB discovery**: Replace `puppetdb_query` and Redis role discovery with static inventory/group membership, a dynamic inventory plugin, DNS/service discovery, or a controlled facts API. Define whether Redis is truly clustered; the reviewed install code configures a Redis instance but does not clearly create cluster membership.
- **Bolt plans/tasks**: Convert `base_utils::health_check` to Ansible ad-hoc/playbook health checks and `rolling_restart` to a serial play with `serial: 1`, health validation, and delay. Preserve failure/abort semantics.

### Security Considerations

- **Encrypted Hiera secrets**: Application DB password and HAProxy stats password are stored as `ENC[PKCS7,...]` values and depend on the node-specific eyaml key paths in `hiera.yaml`. Decrypt only through an approved migration process; re-encrypt into Ansible Vault or an enterprise secret manager, rotate credentials if exposure is suspected, and never commit plaintext values.
- **Default credentials**: Redis has a literal `redis_password = 'CHANGEME'`; the application secret key defaults to `changeme`. Treat these as insecure fail-safe defaults. Make credentials mandatory or fail validation in Ansible and rotate before production cutover.
- **Application environment file**: `.env` is mode `0600`, but contains database/application secrets via the template. Preserve restrictive ownership and permissions, use `no_log: true` where variables could appear, and ensure Ansible diff output does not expose values.
- **Database command injection risk**: Puppet constructs SQL commands by interpolating database username/password/name into shell strings. The Ansible implementation should use `community.postgresql` modules and safe parameters, not shell interpolation.
- **Git access**: The application repository URL is public-looking but repository authentication is not specified. Define deploy-key/token handling in Vault and pin a commit or immutable release rather than tracking `main` in production.
- **HAProxy stats and TLS**: The stats endpoint is enabled on port 9000, with a credential and no visible source restriction. Restrict management access by source network/firewall, use a Vault-managed password, and validate that TLS is enabled and certificates/private keys are deployed with correct permissions. Production data requests TLS 1.3 and stronger ciphers, while common data has SSL disabled; environment precedence must be tested.
- **HAProxy firewall behavior**: Current UFW commands allow ports 80/443 and optionally stats globally. Translate this deliberately and avoid enabling a host firewall without an approved baseline or rollback procedure.
- **Redis network exposure**: Redis is configured with `bind => '0.0.0.0'`. This is high risk even with a password. Bind to cluster/application networks, restrict firewall access, enable TLS if required by policy, and verify cluster authentication/ACL requirements.
- **SSH, logging, and service accounts**: Common data disables root SSH login; base profiles install chrony and rsyslog. Preserve these controls, use system users and `nologin` shells, and validate log destinations and retention.
- **Certificates and keys**: HAProxy references `/etc/ssl/certs` and `/etc/ssl/private`, but certificate provisioning is not visible in reviewed files. Inventory the actual certificate source and migrate it separately using Vault/PKI, strict modes, and renewal automation.

### Technical Challenges

- **Duplicate module copies and precedence**: Root and `site/modules/linux` copies have similar names but different metadata and, for HAProxy, different class ordering (`discover` exists only in the site copy). First establish which copy is active for each deployment and produce a behavior comparison; then converge on one Ansible role per capability.
- **Hiera hierarchy translation**: Hiera uses per-node encrypted data, environment data, common data, OS data, datacenter/cluster/node data, and deep hash merge. Map each level to documented Ansible inventory groups/host vars and Vault files, with automated precedence tests for production, staging, Frankfurt, Debian, and RHEL targets.
- **Ordering and handlers**: Puppet resource graph guarantees installation before configuration and service restart after changes. Recreate this with task order, handlers, `notify`, `listen`, health checks, and explicit `until`/validation steps. Application migrations must not run concurrently with unsafe service changes.
- **Platform divergence**: Ubuntu UFW, Debian package names, RHEL package names, systemd paths, and Rocky test behavior require OS-specific vars and CI coverage.
- **Redis cluster semantics are incomplete**: The code queries PuppetDB but the reviewed install manifest only configures Redis. Confirm whether clustering, replication, Sentinel, or merely multiple independent nodes is intended before implementation.
- **Non-idempotent shell operations**: `pip install`, SQL `exec`, UFW commands, systemd reloads, and backup/migration scripts need module-based or carefully guarded Ansible replacements.
- **Operational cutover**: HAProxy and application nodes are traffic-bearing. Use serial deployment, drain/maintenance handling, health checks, rollback to Puppet or previous role versions, and an overlap period.
- **Testing gap**: Existing tests are centered on Puppet in a Rocky Linux container and a Vagrant Ubuntu VM. Build Molecule scenarios for application, HAProxy, Redis, base OS, and combined roles, including check mode, idempotence, secret redaction, and failure recovery.

### Migration Order

1. **Inventory and source-of-truth reconciliation**: Identify active module copies, collect the complete Hiera data set and eyaml key ownership, document production/staging/node mappings, and freeze unreviewed Puppet changes.
2. **Base OS and `base_utils`**: Implement package helpers, MOTD, chrony, rsyslog, users, validation, health checks, and rolling restart patterns. This establishes shared conventions and test scaffolding.
3. **HAProxy**: Migrate configuration templates, backend data, service handlers, TLS references, firewall policy, and validation. It is independently testable and benefits from explicit traffic-draining/canary procedures.
4. **Redis**: Implement secure standalone/cluster behavior only after confirming intended topology. Migrate persistence, memory policy, authentication, network restrictions, and node discovery/inventory.
5. **Application stack**: Migrate Python runtime, Git checkout, virtualenv, dependencies, PostgreSQL provisioning, environment file, migrations, systemd, logging, backup, and monitoring. This is the highest-risk role because it combines application lifecycle and data changes.
6. **Role/playbook integration and cutover**: Compose base + application/HAProxy/Redis groups, run staging and canary nodes, compare outputs and service health with Puppet, then perform serial production migration with rollback readiness.

Indicative timeline: 1 week discovery/design, 1 week base and test harness, 1–2 weeks HAProxy, 1 week Redis, 2 weeks application/database, and 1–3 weeks integration, security review, staging, documentation, and production rollout. Add time if certificate issuance, secret rotation, Redis clustering, or undiscovered data hierarchies are substantial.

### Assumptions

- Puppet is the source technology; no Chef, Salt, or PowerShell modules are present in the supplied tree.
- The listed `manifests/init.pp` paths are the deployable module entrypoints; the failed search result is due to the repository search pattern/tool behavior, not evidence that the tree lacks those files.
- `site/modules/linux` is earlier or alternate content selected by modulepath precedence, but the exact deployment environment and active copy are not proven by the reviewed files.
- The root and site module copies may be duplicates rather than intentionally separate products; migration must confirm this.
- Ubuntu 24.04 is the primary target because it is explicit in metadata and Vagrant; RHEL/Rocky support is retained as a required compatibility target because it appears in site metadata and tests.
- No production cloud provider, DNS provider, load-balancer control plane, or managed database service is specified.
- PostgreSQL is local only when `db_host` is `localhost`; remote database provisioning, backup transport, retention, and restore testing are not fully described.
- The application repository, requirements, runtime version, backup destination, monitoring integration, and logrotate behavior require confirmation.
- HAProxy certificate deployment and renewal are outside the reviewed module entrypoints and must be discovered before cutover.
- The eyaml private/public keys are available to an authorized migration team; if not, secrets must be rotated rather than recovered.
- `profile_redis_cluster` is intended to provide a real Redis cluster, although the reviewed code does not demonstrate cluster formation or replication.
- PuppetDB is available in the current environment, but its endpoint, query results, and replacement inventory source are unspecified.
- The `discover` manifest and all non-entrypoint templates/data may contain additional behavior not covered by this high-level survey; targeted review is required before implementation.
- The migration team will preserve service names, paths, ports, users, file modes, and externally visible endpoints unless an approved design changes them.
- Ansible Vault or an enterprise secret manager will be selected before any secret-bearing role is merged.
- Platform, application, database, network/security, and operations owners will provide acceptance tests and approve staged cutover/rollback procedures.
