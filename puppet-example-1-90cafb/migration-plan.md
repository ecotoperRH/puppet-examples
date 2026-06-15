# MIGRATION FROM PUPPET TO ANSIBLE

## Executive Summary

This repository contains a Puppet-based infrastructure configuration for a multi-tier application stack consisting of HAProxy load balancers, Python application servers with PostgreSQL databases, and Redis cache clusters. The migration to Ansible will require converting Puppet modules, profiles, and roles to equivalent Ansible roles and playbooks while preserving the hierarchical data structure currently implemented with Hiera.

**Estimated Timeline:**
- Analysis and Planning: 1 week
- Core Module Migration: 3 weeks
- Testing and Validation: 2 weeks
- Documentation and Knowledge Transfer: 1 week
- Total: 7 weeks

**Complexity Assessment:** Medium to High
- Multiple interconnected components with strict dependency chains
- Secrets management with eyaml
- Service discovery patterns using PuppetDB queries

## Module Migration Plan

This repository contains Puppet modules that need individual migration planning:

### MODULE INVENTORY

- **profile_app_stack**:
    - Description: Python application stack with PostgreSQL database and systemd service management
    - Path: modules/profile_app_stack
    - Technology: Puppet
    - Key Features: Git-based application deployment, PostgreSQL database configuration, Python virtual environment management, systemd service configuration, application monitoring

- **profile_haproxy**:
    - Description: HAProxy load balancer with multi-backend support, SSL termination, and statistics interface
    - Path: modules/profile_haproxy
    - Technology: Puppet
    - Key Features: Dynamic backend configuration, SSL certificate management, firewall rules, statistics interface with authentication

- **profile_redis_cluster**:
    - Description: Redis cache cluster with PuppetDB node discovery
    - Path: modules/profile_redis_cluster
    - Technology: Puppet
    - Key Features: Redis configuration, memory management, cluster node discovery via PuppetDB

- **profile::base::base**:
    - Description: Base OS configuration applied to all nodes
    - Path: site/profile/manifests/base/base.pp
    - Technology: Puppet
    - Key Features: NTP configuration, syslog setup, utility package installation

### Infrastructure Files

- `Puppetfile`: Defines external module dependencies (puppetlabs-stdlib, puppetlabs-concat, puppetlabs-firewall, puppetlabs-vcsrepo, puppet-redis, puppetlabs-apt)
- `hiera.yaml`: Hierarchical data configuration with eyaml for encrypted secrets
- `data/common.yaml`: Common configuration values for all environments
- `data/environment/*.yaml`: Environment-specific configuration overrides
- `Vagrantfile`: Development environment configuration using Ubuntu 24.04
- `vagrant-provision.sh`: Provisioning script for Vagrant development environment
- `test/site.pp`: Test manifest for local development
- `x2a-rules/b7646930-b596-47b3-aea4-49ea46a90e69.md`: Migration rule for GitHub Actions CI integration

### Target Details

- **Operating System**: Ubuntu 24.04 (Noble Numbat) based on Vagrantfile and vagrant-provision.sh
- **Virtual Machine Technology**: Vagrant with libvirt provider
- **Cloud Platform**: Not specified, appears to be designed for on-premises or generic cloud deployment

## Migration Approach

### Key Dependencies to Address

- **puppetlabs-stdlib (9.7.0)**: Replace with Ansible built-in filters and modules
- **puppetlabs-concat (9.0.2)**: Replace with Ansible's template module and filters
- **puppetlabs-firewall (8.1.3)**: Replace with Ansible's `iptables` or `firewalld` modules
- **puppetlabs-vcsrepo (6.1.0)**: Replace with Ansible's `git` module
- **puppet-redis (11.0.0)**: Replace with Ansible Redis role (community.general.redis or custom role)
- **puppetlabs-apt (9.4.0)**: Replace with Ansible's `apt` module

### Security Considerations

- **Hiera eyaml encrypted secrets**: Migrate to Ansible Vault for secret storage
  - Encrypted node-specific data in `nodes/%{trusted.certname}.yaml`
  - Database credentials in profile_app_stack
  - HAProxy statistics interface credentials
  - Redis password
  
- **SSL/TLS Configuration**:
  - HAProxy SSL certificate and key paths
  - SSL cipher configuration and minimum TLS version settings

- **Vault/secrets management**:
  - 5 credentials detected in profile_app_stack (db_user, db_password, app_user credentials, secret_key)
  - 2 credentials detected in profile_haproxy (stats_user, stats_password)
  - 1 credential detected in profile_redis_cluster (redis_password)

### Technical Challenges

- **PuppetDB Query Replacement**: The `puppetdb_query` function used for Redis cluster node discovery needs an alternative approach in Ansible
  - Mitigation: Use Ansible inventory groups or dynamic inventory plugins to replace PuppetDB node discovery

- **Strict Dependency Chains**: Puppet's explicit dependency chains (`->`, `~>`) need to be translated to Ansible's task ordering and handlers
  - Mitigation: Use Ansible's `notify`, `handlers`, and explicit task dependencies with `when` conditions

- **Hierarchical Data**: Puppet's Hiera hierarchical data structure needs to be mapped to Ansible's variable precedence system
  - Mitigation: Use Ansible's group_vars, host_vars, and variable precedence rules to implement similar hierarchy

- **Custom Functions**: Custom Puppet functions like `profile_app_stack::app_db_url` need to be reimplemented as Ansible filters or lookup plugins
  - Mitigation: Develop custom Ansible filters or use Jinja2 templates to replace custom Puppet functions

### Migration Order

1. **Base Profile** (Low complexity, foundation for other roles)
   - Migrate profile::base::base to Ansible role
   - Implement common configurations (NTP, syslog, utilities)

2. **HAProxy Profile** (Medium complexity)
   - Migrate profile_haproxy to Ansible role
   - Implement configuration templates, SSL setup, and firewall rules

3. **Redis Cluster Profile** (Medium complexity)
   - Migrate profile_redis_cluster to Ansible role
   - Implement alternative to PuppetDB node discovery

4. **Application Stack Profile** (High complexity)
   - Migrate profile_app_stack to Ansible role
   - Implement Python app deployment, database setup, and service management
   - Ensure proper dependency handling between components

### Assumptions

1. The target environment will continue to be Ubuntu 24.04 as specified in the Vagrantfile
2. The application architecture will remain the same (HAProxy → Python App → PostgreSQL + Redis)
3. The current security model using encrypted secrets will be maintained
4. Development workflow with Vagrant will be preserved
5. No changes to the underlying application code or deployment strategy
6. The PuppetDB query functionality is only used for Redis cluster node discovery
7. The eyaml encrypted secrets are not accessible during migration planning
8. The GitHub Actions CI integration requirement will be implemented as specified in the x2a-rules
9. The current module structure will be mapped to equivalent Ansible roles
10. The test environment setup will be migrated to Ansible playbooks