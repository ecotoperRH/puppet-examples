# MIGRATION FROM PUPPET TO ANSIBLE

This repository is a Puppet 7/8 Linux control repository migrating to Ansible. It manages a Python application stack with PostgreSQL connectivity, HAProxy load balancers, Redis nodes, and shared utilities. The migration is medium/high complexity because the repository contains seven Puppet module directories with `manifests/init.pp`, duplicated module implementations selected through module-path precedence, Hiera v5 data with EYAML secrets, explicit Puppet resource ordering, and PuppetDB-based discovery. A small team should plan approximately 8–12 weeks for inventory, role development, testing, staged rollout, and documentation; a pilot can be completed in 2–3 weeks.

## Module Migration Plan

This repository contains Puppet modules, site profiles, roles, Hiera data, and test/provisioning assets that require individual migration planning.

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
The following seven entries correspond exactly to the seven directories shown in the repository tree that contain `manifests/init.pp`. Each is listed separately, including the duplicated Linux implementations. No external dependencies are included in this inventory.

- **profile_app_stack — top-level module**:
    - Description: Python application stack orchestrator that resolves application, database, worker, logging, and secret parameters and enforces Python → database → application → systemd service → monitoring ordering.
    - Path: `modules/profile_app_stack`
    - Technology: Puppet
    - Key Features: Git-based application deployment, Python packages, PostgreSQL connection settings, Gunicorn/Uvicorn-style workers, systemd service, log rotation, backup and health-check files, and a custom database-URL function.

- **profile_haproxy — top-level module**:
    - Description: HAProxy load-balancer profile coordinating installation, configuration, service management, and firewall configuration.
    - Path: `modules/profile_haproxy`
    - Technology: Puppet
    - Key Features: Deep-merged backend maps, HTTP health checks, stats configuration, timeouts, logging, optional TLS, custom HTTP error pages, and firewall management.

- **profile_redis_cluster — top-level module**:
    - Description: Redis profile that installs and configures Redis with authentication, persistence, memory controls, and PuppetDB-oriented node discovery.
    - Path: `modules/profile_redis_cluster`
    - Technology: Puppet
    - Key Features: `puppet-redis` integration, AOF persistence, every-second fsync, password protection, configurable port and memory, and Redis-node query logic.

- **base_utils — common site module**:
    - Description: Shared utility module for base package installation, MOTD management, helper functions/types, facts, Bolt plans, and a service-check task.
    - Path: `site/modules/common/base_utils`
    - Technology: Puppet/Bolt
    - Key Features: Debian/Red Hat/Ubuntu data, managed `/etc/motd`, utility package lists, reusable directory/config/notification resources, `health_check` and `rolling_restart` plans, and a shell task.

- **profile_app_stack — Linux site module**:
    - Description: Linux site implementation of the Python/PostgreSQL application-stack orchestrator with the same strict phase dependency chain and environment-driven application settings.
    - Path: `site/modules/linux/profile_app_stack`
    - Technology: Puppet
    - Key Features: Environment-specific revisions, Python dependencies, application and database configuration, systemd service templates, logging, backup and health-check scripts, and a custom database-URL function.

- **profile_haproxy — Linux site module**:
    - Description: Linux site implementation of the HAProxy load-balancer profile with installation, configuration, discovery, service, and firewall phases.
    - Path: `site/modules/linux/profile_haproxy`
    - Technology: Puppet
    - Key Features: Multi-backend configuration, datacenter/cluster/node Hiera layers, Debian/Red Hat data, production stick tables, health checks, TLS settings, custom errors, and dynamic discovery.

- **profile_redis_cluster — Linux site module**:
    - Description: Linux site implementation of the Redis profile, configuring Redis and querying PuppetDB for nodes assigned the Redis profile class.
    - Path: `site/modules/linux/profile_redis_cluster`
    - Technology: Puppet
    - Key Features: Redis authentication, bounded memory, append-only persistence, package/service management, log-directory handling, and PuppetDB-oriented discovery.

### Infrastructure Files

- `Puppetfile`: Pins `puppetlabs-stdlib` 9.7.0, `puppetlabs-concat` 9.0.2, `puppetlabs-firewall` 8.1.3, `puppetlabs-vcsrepo` 6.1.0, `puppet-redis` 11.0.0, and `puppetlabs-apt` 9.4.0. Replace these with Ansible collections or native modules.
- `environment.conf`: Sets module precedence to `site/modules/linux:site/modules/common:site:modules`; this means site Linux modules can shadow top-level modules.
- `hiera.yaml`: Defines Hiera v5 YAML lookup using encrypted per-node EYAML data, environment data, and common data. Translate this to inventory, `group_vars`, `host_vars`, role defaults, and Vault.
- `data/`, module `data/`, and site-module `data/`: Hold common, environment, OS, datacenter, cluster, and node settings, including HAProxy backend maps and application revisions.
- `site/role/manifests/app_stack.pp`, `haproxy.pp`, and `redis_cluster.pp`: Compose base and capability profiles. Replace with Ansible inventory groups and playbook/role composition.
- `site/profile/manifests/`: Contains thin base, application, HAProxy, and Redis profile wrappers. Map these to Ansible roles, tags, and role interfaces.
- `test/site.pp`, `test/hiera.yaml`, and `test/data/common.yaml`: Puppet test fixture that creates a local Git repository, applies all three service profiles, and supplies test credentials. Replace with Molecule and CI scenarios.
- `Vagrantfile`: Uses Vagrant/libvirt, Ubuntu 24.04, private address `192.168.121.10`, ports 80/443 forwarding, 2 GB RAM, and 2 CPUs.
- `vagrant-provision.sh`: Installs Puppet 8 and pinned modules, copies top-level modules, applies the test manifest, and checks HAProxy and Redis. Replace with Ansible provisioning.
- `puppetdb_query_stub/`: Support function stub without `manifests/init.pp`; it is not one of the seven deployable Puppet modules.

## Target Details

- **Operating System**: Ubuntu 24.04 is explicit in the Vagrant box and top-level module metadata. Site metadata also supports Ubuntu 22.04/24.04, Debian 11/12, and Red Hat 8/9. Confirm production before implementation; prioritize Ubuntu 24.04 and test other families separately.
- **Virtual Machine Technology**: Vagrant with the libvirt provider is explicitly used for local testing. Production virtualization is not specified.
- **Cloud Platform**: Not specified. No AWS, Azure, GCP, or cloud-init configuration was identified.

## Migration Approach

### Key Dependencies to Address

- **Puppet 7/8 and Hiera v5**: Replace class parameter lookups with Ansible role interfaces and documented variable precedence. Convert deep Hiera merges into explicit structured variables.
- **puppetlabs-stdlib 9.x**: Replace helper functions/types with native Ansible filters, validation, and task logic.
- **puppetlabs-concat 9.0.2**: Replace fragment concatenation with Jinja2 templates and validate HAProxy configuration before reload.
- **puppetlabs-firewall 8.1.3**: Use `ansible.posix.firewalld` or `community.general.ufw`, selected by OS family.
- **puppetlabs-vcsrepo 6.1.0**: Use `ansible.builtin.git` with pinned revisions, ownership, and safe update behavior.
- **puppet-redis 11.0.0**: Use a maintained Redis Ansible role/collection or native package, template, service, and directory tasks.
- **puppetlabs-apt 9.4.0**: Use `ansible.builtin.apt_repository`, `apt`, and cache tasks where repositories are required.
- **PuppetDB and custom Puppet functions**: Replace Redis discovery and any HAProxy discovery with inventory, dynamic inventory, or an agreed service-discovery system. Reimplement database-URL construction with safe URL encoding.
- **systemd/application runtime**: Use ordered role tasks, handlers, `ansible.builtin.systemd_service`, Git checkout, Python package installation, migrations, and health checks.

### Security Considerations

- **EYAML secrets**: Database passwords, production application secret keys, and HAProxy stats credentials appear as `ENC[PKCS7,...]`. Move them to Ansible Vault or an approved external secret manager, and do not expose them in templates, logs, facts, or task output.
- **Plaintext test/default secrets**: Test data contains database, HAProxy, Redis, and application secrets; Redis defaults include `CHANGEME`. Keep test secrets in CI secret storage and rotate any real values.
- **Redis exposure**: Redis binds to `0.0.0.0` and uses a password. Restrict bind addresses and firewall access, protect `redis.conf`, and assess the need for TLS.
- **HAProxy statistics and TLS**: Stats are enabled by default but disabled in production. Production enables TLS with TLS 1.2 minimum and configured ciphers. Define certificate/key delivery, permissions, renewal, and Vault integration.
- **Database URL handling**: Preserve credentials without leaking them through process arguments or rendered world-readable files; use `no_log` carefully.
- **Least privilege**: Preserve root ownership for system configuration, application user/group ownership, Redis log ownership, service-user boundaries, and restrictive secret-file modes.
- **SSH/logging settings**: Root Hiera data specifies root-login hardening and syslog destinations, but the reviewed module inventory does not prove which module applies them. Confirm ownership before migration.

### Technical Challenges

- **Duplicate implementations and precedence**: The seven modules include top-level and Linux site copies. The site module path has higher precedence, while Vagrant copies top-level modules. Diff the copies and designate a canonical behavior before implementation.
- **Puppet ordering and refresh semantics**: Explicit arrows and notifications must become ordered Ansible tasks and handlers, especially for application deployment, HAProxy reloads, and monitoring.
- **Hiera hierarchy**: Backend data is split across common, environment, datacenter, cluster, node, and OS layers. Produce and test a final-variable matrix for staging, production, and representative nodes.
- **Dynamic topology**: PuppetDB discovery has no direct Ansible equivalent. Define inventory ownership, membership updates, convergence timing, and failure behavior.
- **Cross-platform support**: Package names, service names, firewall implementations, paths, and HAProxy/Redis defaults vary across Ubuntu, Debian, and Red Hat.
- **Application deployment**: Preserve Git revision pinning, virtual-environment/package behavior, migrations, systemd restart policy, log rotation, backup behavior, and rollback.
- **Testing**: Replace Puppet apply validation with Molecule scenarios for base utilities, HAProxy, Redis, and the application, including rendered config checks and service-level tests.

### Migration Order

1. Resolve module precedence, compare the seven modules, freeze effective Puppet catalogs, and inventory every Hiera key.
2. Establish Ansible repository standards, inventories, Vault integration, CI, Molecule, and supported OS matrix.
3. Migrate `base_utils` and confirmed common hardening/logging behavior.
4. Migrate HAProxy, including backends, TLS, firewall, health checks, and safe reloads.
5. Migrate Redis, including persistence, authentication, firewalling, and replacement of PuppetDB discovery.
6. Migrate the application stack, including Python runtime, Git deployment, PostgreSQL settings, systemd, monitoring, backup, and logging.
7. Replace Puppet roles/profiles with playbooks and inventory groups; perform canary and staged production cutover with rollback.

### Assumptions

- The source technology is Puppet; no Chef, Salt, or PowerShell module entrypoints were identified.
- Exactly seven repository directories contain Puppet `manifests/init.pp` entrypoints: the seven paths listed in MODULE INVENTORY.
- The top-level and site Linux copies overlap and may differ; `environment.conf` indicates site Linux precedence, while the Vagrant script deliberately tests top-level modules.
- Ubuntu 24.04 is the confirmed local target, not proof of the production OS.
- PostgreSQL appears as an application dependency and connection target; the reviewed entrypoints do not establish that PostgreSQL itself is installed by this repository.
- Certificate sources, production inventory, Redis membership, and final service-discovery ownership require confirmation.
- EYAML private/public keys are external to the repository and must be available or replaced during migration.
- Timeline assumes a platform lead, Ansible engineer, application/database owner, security reviewer, staging access, and CI support.
- Teams should maintain a Puppet-to-Ansible behavior matrix, require rendered-config review, assign owners for application, networking/load balancing, data services, security, and testing, and retain Puppet as rollback until acceptance criteria pass.
