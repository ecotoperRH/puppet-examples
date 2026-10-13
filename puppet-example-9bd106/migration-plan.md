# MIGRATION FROM PUPPET TO ANSIBLE

This repository is a Puppet 7 control repository targeting primarily Ubuntu 24.04, with reusable profiles, roles, Hiera YAML data, custom Facter/Puppet functions, templates, static files, Bolt tasks/plans, and a Vagrant/libvirt test path. The migration is medium-to-high complexity: the resource operations are familiar to Ansible, but the Hiera precedence model, duplicated module trees, PuppetDB-based Redis discovery, custom functions, strict resource ordering, and encrypted values require deliberate redesign. A realistic delivery is approximately 6–10 weeks for one experienced engineer, or 3–5 weeks with two engineers plus application/network/security reviewers, including parity testing and staged rollout.

## Module Migration Plan

This repository contains Puppet modules, site profiles, and roles that need individual migration planning. The `modules/` and `site/modules/linux/` trees contain overlapping implementations; they must be reconciled rather than blindly migrated twice.

### MODULE INVENTORY

- **profile_app_stack (root module)**:
    - Description: Application-stack orchestration for a Python application, local PostgreSQL integration, deployment from Git, systemd service management, logging/monitoring, and a strict Python → database → application → service → monitoring dependency chain.
    - Path: `modules/profile_app_stack`
    - Technology: Puppet
    - Key Features: Hiera-driven application and database parameters, custom `app_db_url` function, Git revision deployment, Python packages, systemd unit and environment files, log rotation, health/backup scripts.

- **profile_haproxy (root module)**:
    - Description: HAProxy load-balancer profile with package installation, generated configuration, backend pools, statistics endpoint, logging, optional TLS, service management, and firewall rules.
    - Path: `modules/profile_haproxy`
    - Technology: Puppet
    - Key Features: Deep-merged backend maps, ERB/EPP configuration templates, custom HAProxy Facter version discovery, custom error pages, stats credentials, SSL cipher/minimum-version settings.

- **profile_redis_cluster (root module)**:
    - Description: Redis installation/configuration profile intended to form a cluster using PuppetDB discovery of nodes running the Redis profile.
    - Path: `modules/profile_redis_cluster`
    - Technology: Puppet
    - Key Features: Redis port, password, maxmemory and eviction policy parameters; `puppet-redis` dependency; custom `redis_role` fact; PuppetDB query function.

- **base_utils**:
    - Description: Common host utilities and helper abstractions used by the base profile, including MOTD management and configurable utility package installation.
    - Path: `site/modules/common/base_utils`
    - Technology: Puppet
    - Key Features: OS-specific Hiera data for Debian/Red Hat, custom types/functions, MOTD template, Facter platform information, Bolt health-check task and rolling-restart plan.

- **profile_app_stack (Linux site implementation)**:
    - Description: Linux site implementation of the Python/PostgreSQL application stack. Its entrypoint and metadata mirror the root application module but add explicit Red Hat 8/9 support.
    - Path: `site/modules/linux/profile_app_stack`
    - Technology: Puppet
    - Key Features: Same strict orchestration and deployment concerns as the root module; includes duplicated templates, scripts, data, metadata, and custom database URL function.

- **profile_haproxy (Linux site implementation)**:
    - Description: Linux site implementation of the HAProxy load-balancer profile, including install/configuration/discovery/service/firewall phases.
    - Path: `site/modules/linux/profile_haproxy`
    - Technology: Puppet
    - Key Features: Debian and Red Hat OS data, datacenter/cluster/node/environment hierarchy, dynamic discovery phase, backend templates, custom error pages, TLS and stats configuration.

- **profile_redis_cluster (Linux site implementation)**:
    - Description: Linux site implementation of the Redis cluster profile using PuppetDB discovery and the `puppet-redis` module.
    - Path: `site/modules/linux/profile_redis_cluster`
    - Technology: Puppet
    - Key Features: Redis tuning and credentials, `redis_role` fact, cluster discovery behavior, Redis configuration template.

The `site/profile/manifests/` classes are thin Puppet profile wrappers (`profile::base::base`, `profile::app::stack`, `profile::loadbalancer::haproxy`, and `profile::cache::redis`), while `site/role/manifests/` defines the three deployment roles: `role::app_stack`, `role::haproxy`, and `role::redis_cluster`. They should become Ansible role assignments, playbooks, or inventory group mappings rather than separate infrastructure modules. `puppetdb_query_stub` has no `manifests/init.pp`; it is a custom-function support stub, not a standalone Puppet module entrypoint.

**CRITICAL PATH VERIFICATION:**
All paths above were present in the supplied repository tree and the module entrypoints were read. The duplicate root/Linux module paths are intentionally listed separately because they are separate module directories with their own `manifests/init.pp`; migration should first establish which copy is authoritative.

### Infrastructure Files

- `Puppetfile`: Pins Puppet Forge dependencies: stdlib 9.7.0, concat 9.0.2, firewall 8.1.3, vcsrepo 6.1.0, redis 11.0.0, and apt 9.4.0. Replace each with native Ansible modules, collections, or explicit role code.
- `environment.conf`: Defines module precedence (`site/modules/linux`, `site/modules/common`, `site`, `modules`) and therefore explains why Linux-site copies can override root copies. Preserve the intended precedence in Ansible inventory/group_vars and role selection, not by retaining duplicate code.
- `hiera.yaml`: Defines Hiera 5 YAML lookup with a 3-level effective hierarchy shown here: encrypted per-node data, environment data, then common data. The comments refer to a much deeper HAProxy hierarchy, but this root configuration does not implement those levels; this discrepancy must be resolved.
- `data/`: Environment-wide NTP, SSH, and logging defaults and production/staging overrides. Some keys reference `ntp::` and `syslog::` namespaces without corresponding modules visible in this repository.
- `modules/*/data`, `site/modules/linux/*/data`: Module-scoped application, HAProxy, and OS/datacenter/cluster/node data. Convert to inventory, `group_vars`, `host_vars`, and role defaults/vars with a documented precedence policy.
- `site/profile/manifests` and `site/role/manifests`: Composition layer for base, application, HAProxy, and Redis roles. This is the primary source for Ansible playbook/group design.
- `templates/` and `files/`: Convert ERB/EPP templates into Jinja2 templates and preserve static error pages/scripts only after reviewing ownership, mode, and execution behavior in their consuming manifests.
- `modules/puppetdb_query_stub/lib/puppet/functions/puppetdb_query.rb`: Custom Puppet function support. The Redis migration must replace its runtime discovery behavior; it cannot be translated directly into a normal Ansible task.
- `Vagrantfile`: Uses `bento/ubuntu-24.04`, libvirt, 2 CPUs, 2 GB RAM, private IP `192.168.121.10`, forwarded HTTP/HTTPS ports, and rsync to `/puppet-repo`. Adapt this to an Ansible-compatible test invocation while retaining Ubuntu 24.04 coverage.
- `vagrant-provision.sh`: Existing Puppet installation/provisioning bootstrap; replace with Ansible installation and test execution or use Molecule/Testinfra.
- `test/Containerfile`, `test/run.sh`, `test/site.pp`, `test/data`, `test/hiera.yaml`: Container/test harness and a fixture Git repository for the application. Port assertions and convergence tests to Molecule, Testinfra, or an equivalent CI harness.

### Target Details

- **Operating System**: Ubuntu 24.04 is explicit in the Vagrant box and in several module metadata files. The Linux site data and metadata also indicate Debian 11/12 and Red Hat Enterprise Linux 8/9 support, while `base_utils` supports Red Hat 8/9, Debian 11/12, and Ubuntu 22.04/24.04. Establish Ubuntu 24.04 as the initial acceptance target and test any retained RHEL/Debian support separately.
- **Virtual Machine Technology**: libvirt through Vagrant is explicitly specified. The production virtualization platform is not specified.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP-specific configuration is visible.

## Migration Approach

### Key Dependencies to Address

- **Puppet 7.x (<9)**: Replace Puppet catalog compilation and ordering with Ansible play/task ordering, handlers, check mode, and idempotent modules.
- **puppetlabs-stdlib 9.7.0**: Replace helper functions/types with native Ansible filters, validations, facts, and role defaults.
- **puppetlabs-concat 9.0.2**: Replace concatenated fragments with one Jinja2-rendered HAProxy configuration or explicit managed fragments where operationally required.
- **puppetlabs-firewall 8.1.3**: Use the appropriate `ansible.posix.firewalld` or `community.general.ufw` collection after confirming the target firewall. Current data explicitly names UFW for Debian and disables SELinux there.
- **puppetlabs-vcsrepo 6.1.0**: Use `ansible.builtin.git`, with explicit repository, revision, ownership, and deployment atomicity behavior.
- **puppet-redis 11.0.0**: Replace with an Ansible Redis role or a maintained collection plus explicit package, configuration, service, and cluster tasks. Validate Redis version and cluster semantics rather than assuming the Puppet module behavior.
- **puppetlabs-apt 9.4.0**: Use `ansible.builtin.apt_repository`, package, cache, and key-management tasks where repository management is actually used.
- **PostgreSQL/Python application dependencies**: Preserve the application’s Python requirements (FastAPI, Uvicorn, Gunicorn, psycopg, Alembic in the test fixture) through a virtualenv or packaged deployment strategy. PostgreSQL server provisioning details are in subordinate manifests not reviewed here and require implementation-level follow-up.
- **PuppetDB and custom discovery**: Replace the Redis PuppetDB query with explicit inventory groups, generated cluster membership, service discovery, or a controlled external inventory plugin. Do not run discovery by querying Ansible facts during a host’s configuration without defining convergence behavior.

### Security Considerations

- **Encrypted database credential**: `profile_app_stack::db_password` is visible as a Puppet EYAML `ENC[PKCS7,...]` value. Decrypt/re-encrypt into Ansible Vault or an approved external secret manager; never copy the ciphertext into ordinary `group_vars` without a compatible decryption process.
- **HAProxy stats credential**: The root HAProxy data contains an EYAML-encrypted `stats_password`; the Linux entrypoint uses `Sensitive[String]`. Store it in Ansible Vault and ensure templates do not expose it through logs, diffs, or debug output.
- **Redis password**: Both Redis entrypoints show the default literal `CHANGEME`. Treat this as an unsafe fallback, require a vaulted value, rotate any deployed credential, and fail the play if the value remains unchanged.
- **Application secret key**: The application entrypoint defaults `secret_key` to `changeme`. Make it mandatory or vault-backed in Ansible and rotate it where used.
- **TLS material**: HAProxy supports TLS, with certificate and private-key paths under `/etc/ssl/certs` and `/etc/ssl/private`, but the reviewed common data disables SSL by default. Confirm whether production enables it, migrate certificates securely, enforce private-key ownership/mode, and retain TLS minimum version/cipher policy.
- **SSH and service hardening**: Common data disables root SSH login and sets client-alive interval. Preserve these settings only after confirming the full SSH module/configuration exists; avoid silently claiming hardening that the visible roles do not implement.
- **Firewall and exposure**: HAProxy has a firewall phase, HTTP/HTTPS forwarded ports in Vagrant, and a stats port 9000. Define a minimal inbound policy, restrict the stats endpoint, and test both UFW and any RHEL firewall implementation.
- **File permissions and secrets in generated environment files**: Review `app.env.erb`, service templates, backups, and logs before migration. Use `no_log`, restrictive modes, separate secret files, and systemd credential/environment mechanisms where suitable.

### Technical Challenges

- **Duplicate implementations and precedence**: Root modules and Linux site modules overlap but differ in supported OS and HAProxy discovery behavior. Freeze the authoritative implementation, compare subordinate manifests/data/templates, and migrate only the selected behavior.
- **Hiera-to-inventory redesign**: Puppet lookup is implicit and layered; Ansible requires an explicit inventory model. Map environment, OS, datacenter, cluster, node, and backend data to `group_vars`/`host_vars`, document merge rules, and add schema validation for nested backend hashes.
- **Dynamic Redis clustering**: PuppetDB class-resource discovery is not a direct Ansible equivalent and can create ordering/convergence issues. Define cluster membership as inventory or generated data and use a controlled bootstrap/scale workflow, including quorum and failover testing.
- **Ordering and notifications**: The application uses a strict class chain and service refresh semantics. Reproduce this with task blocks, handlers, `notify`, readiness checks, database migration policy, and explicit rolling deployment controls.
- **Custom Puppet functions and facts**: `app_db_url`, `puppetdb_query`, `haproxy_version`, `redis_role`, and base utility facts need native filters, `set_fact`, gathered facts, or purpose-built scripts. Test URL escaping and sensitive-value handling carefully.
- **OS portability**: Package/service names, firewall providers, paths, and SELinux behavior vary across Ubuntu, Debian, and RHEL. Start with Ubuntu 24.04 and gate other platforms behind CI rather than relying on Puppet’s prior metadata.
- **Test parity**: The test fixture provisions a local Git repository and includes a simple Python application. Build convergence, syntax, idempotence, service health, firewall, HAProxy backend, and Redis cluster tests before production cutover.
- **Incomplete source visibility**: The entrypoints reference subordinate manifests and templates not fully reviewed for this high-level survey. Detailed task design must inspect those files and reconcile the actual package, database, monitoring, and firewall resources.

### Migration Order

1. **Foundation and inventory model**: Establish Ansible project structure, collections, Vault policy, linting, CI, Ubuntu 24.04 test image, environment/OS/role groups, and the authoritative source-copy decision.
2. **base_utils and base profile**: Migrate utility packages, MOTD, chrony, rsyslog, SSH-related settings, and common handlers. Validate safe convergence across all target OS families.
3. **HAProxy**: Migrate package/config/service/firewall behavior and static error pages. It has clear boundaries and provides an early end-to-end test of nested inventory data, templates, TLS, and handlers.
4. **Application stack**: Migrate Python runtime, Git deployment, PostgreSQL integration, virtualenv/packages, systemd, environment file, logging, monitoring, backup, and health checks. Resolve secret handling and deployment rollback semantics before cutover.
5. **Redis cluster**: Migrate single-node installation/configuration first, then implement and test explicit cluster membership and rolling operations. This is the highest-risk module because it depends on PuppetDB discovery.
6. **Roles and cutover**: Replace Puppet role assignment with Ansible playbooks, run parallel validation against representative app, load-balancer, and Redis nodes, then perform staged production rollout with rollback to Puppet until health and idempotence criteria pass.

### Assumptions

- Puppet is the only active configuration-management technology; no Chef, Salt, or PowerShell modules are present in the supplied tree.
- The root `Puppetfile` is the dependency lock/source for the repository; nested Puppetfiles under selected modules may need separate review.
- Ubuntu 24.04 is the initial target because it is explicit in Vagrant and module metadata; continued Debian/RHEL support is a migration decision, not assumed parity.
- The Linux site modules may override the root modules through `environment.conf`; their duplication is not assumed to be accidental until owners confirm it.
- The visible Hiera hierarchy is authoritative for the root environment, but comments and module-local hierarchies suggest additional lookup behavior that must be verified.
- EYAML keys are external to this repository and are available to the security/platform team; no attempt should be made to recover them from source.
- The encrypted-looking values are examples or deployed secrets; in either case, Ansible Vault/external secret management is required.
- PostgreSQL installation, monitoring, backup, and firewall details may be implemented in subordinate files not opened for this survey; migration estimates include a discovery/validation phase for them.
- `profile_redis_cluster` is intended to be a cluster, but the reviewed entrypoint only shows discovery and inclusion of its install class; actual cluster formation must be confirmed before implementation.
- The production VM/cloud platform is unspecified beyond the Vagrant/libvirt development path.
- Ansible controller connectivity, privilege escalation, package repositories, Python availability, and service accounts will be provided by the target platform.
- The application repository, its deployment credentials, database schema/migration ownership, and release/rollback policy require confirmation from application owners.
- Teams should assign owners for platform/base, networking/HAProxy, application/database, Redis, security/secrets, and test/CI workstreams; maintain a Puppet-to-Ansible behavior matrix and obtain sign-off per role before disabling Puppet.


## Inventory Completeness Verification

The repository is Puppet-based. The following seven directories each contain a Puppet module entrypoint at `manifests/init.pp`, and each is represented as a separate entry in the MODULE INVENTORY above:

1. `modules/profile_app_stack/manifests/init.pp` → inventory path `modules/profile_app_stack`
2. `modules/profile_haproxy/manifests/init.pp` → inventory path `modules/profile_haproxy`
3. `modules/profile_redis_cluster/manifests/init.pp` → inventory path `modules/profile_redis_cluster`
4. `site/modules/common/base_utils/manifests/init.pp` → inventory path `site/modules/common/base_utils`
5. `site/modules/linux/profile_app_stack/manifests/init.pp` → inventory path `site/modules/linux/profile_app_stack`
6. `site/modules/linux/profile_haproxy/manifests/init.pp` → inventory path `site/modules/linux/profile_haproxy`
7. `site/modules/linux/profile_redis_cluster/manifests/init.pp` → inventory path `site/modules/linux/profile_redis_cluster`

No Chef `recipes/default.rb` or PowerShell `.psd1` module manifests are present in the supplied repository tree. The profile and role manifest directories under `site/profile` and `site/role` are Puppet composition classes, not additional modules with their own `manifests/init.pp`, so they are documented as supporting composition rather than incorrectly counted as separate modules.