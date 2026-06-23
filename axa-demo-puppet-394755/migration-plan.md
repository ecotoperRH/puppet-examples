# MIGRATION FROM PUPPET TO ANSIBLE

## Executive Summary

This repository contains a Puppet-based infrastructure configuration for a multi-tier application stack consisting of HAProxy load balancers, Python application servers with PostgreSQL databases, and Redis clusters. The migration to Ansible will involve converting Puppet modules, profiles, and roles to Ansible roles and playbooks while preserving the hierarchical data structure currently implemented with Hiera.

**Estimated Timeline:**
- Analysis and Planning: 1-2 weeks
- Core Module Migration: 3-4 weeks
- Testing and Validation: 2 weeks
- Documentation and Knowledge Transfer: 1 week
- Total: 7-9 weeks

**Complexity Assessment:** Medium to High
- Multiple interconnected components with strict dependency chains
- Hierarchical configuration data with environment-specific overrides
- Secret management with eyaml
- PuppetDB queries for node discovery that need Ansible alternatives

## Module Migration Plan

This repository contains Puppet modules that need individual migration planning:

### MODULE INVENTORY

- **profile_app_stack**:
    - Description: Python application stack with PostgreSQL database and systemd service management
    - Path: modules/profile_app_stack
    - Technology: Puppet
    - Key Features: Python virtual environment setup, PostgreSQL database configuration, application deployment from Git, systemd service management, monitoring integration

- **profile_haproxy**:
    - Description: HAProxy load balancer with multi-backend support, SSL termination, and statistics interface
    - Path: modules/profile_haproxy
    - Technology: Puppet
    - Key Features: HAProxy installation and configuration, SSL certificate management, backend server configuration, firewall rules, statistics interface with authentication

- **profile_redis_cluster**:
    - Description: Redis cluster configuration with PuppetDB node discovery
    - Path: modules/profile_redis_cluster
    - Technology: Puppet
    - Key Features: Redis server installation, cluster configuration, memory management, PuppetDB integration for node discovery

- **base**:
    - Description: Base OS configuration applied to all nodes
    - Path: site/profile/manifests/base
    - Technology: Puppet
    - Key Features: NTP configuration, syslog setup, utility package installation

### Infrastructure Files

- `Puppetfile`: Defines external module dependencies including puppetlabs-stdlib, puppetlabs-concat, puppetlabs-firewall, puppetlabs-vcsrepo, puppet-redis, and puppetlabs-apt. These will need to be replaced with Ansible Galaxy roles or custom implementations.
- `hiera.yaml`: Defines the hierarchical data lookup structure with environment-specific overrides and encrypted data. Will need to be replaced with Ansible group_vars, host_vars, and Ansible Vault.
- `environment.conf`: Configures the Puppet environment modulepath. No direct equivalent in Ansible, but directory structure will need to be considered.
- `data/*.yaml`: Contains configuration data at various levels of specificity. Will be migrated to Ansible group_vars and host_vars.
- `Vagrantfile`: Defines the development/test environment using Ubuntu 24.04. Can be preserved with minimal changes for Ansible testing.
- `vagrant-provision.sh`: Installs Puppet and applies manifests. Will need to be replaced with Ansible installation and playbook execution.

### Target Details

Based on the source configuration files:

- **Operating System**: Ubuntu 24.04 (Noble Numbat) as specified in the Vagrantfile
- **Virtual Machine Technology**: Libvirt as specified in the Vagrantfile provider configuration
- **Cloud Platform**: Not specified in the repository; appears to be targeting on-premises or generic VM deployment

## Migration Approach

### Key Dependencies to Address

- **puppetlabs-stdlib (9.7.0)**: Replace with Ansible's built-in filters and modules
- **puppetlabs-concat (9.0.2)**: Replace with Ansible's template module and blockinfile/lineinfile modules
- **puppetlabs-firewall (8.1.3)**: Replace with Ansible's ufw or iptables modules
- **puppetlabs-vcsrepo (6.1.0)**: Replace with Ansible's git module
- **puppet-redis (11.0.0)**: Replace with community.general.redis or a dedicated Redis role from Ansible Galaxy
- **puppetlabs-apt (9.4.0)**: Replace with Ansible's apt module

### Security Considerations

- **Hiera eyaml**: The repository uses eyaml for encrypted data. Migration will require:
  - Identifying all encrypted values in Hiera data
  - Converting these to Ansible Vault secrets
  - Ensuring proper access control for vault passwords

- **Database credentials**: The profile_app_stack module contains database credentials that need to be securely managed:
  - db_user, db_password in profile_app_stack::init.pp
  - These should be stored in Ansible Vault

- **Redis password**: The profile_redis_cluster module contains a Redis password:
  - redis_password in profile_redis_cluster::init.pp
  - Should be stored in Ansible Vault

- **HAProxy statistics authentication**:
  - stats_user and stats_password in profile_haproxy::init.pp
  - Should be stored in Ansible Vault

- **SSL certificates**:
  - ssl_cert_path and ssl_key_path in profile_haproxy::init.pp
  - Will need secure handling in Ansible, possibly using ansible-vault or a certificate management system

- **Application secret key**:
  - secret_key in profile_app_stack::init.pp
  - Should be stored in Ansible Vault

### Technical Challenges

- **PuppetDB queries**: The profile_redis_cluster module uses PuppetDB queries for node discovery:
  - Challenge: Ansible doesn't have a direct equivalent to PuppetDB's query language
  - Mitigation: Use Ansible's dynamic inventory, possibly with a custom inventory script or plugin, or use Ansible facts gathering to achieve similar functionality

- **Strict dependency chains**: The profile_app_stack module uses a strict dependency chain with the contain and -> operators:
  - Challenge: Ensuring proper sequencing in Ansible
  - Mitigation: Use Ansible's handlers, meta tasks, and proper task organization to maintain dependencies

- **Custom Puppet functions**: The profile_app_stack module uses a custom function profile_app_stack::app_db_url:
  - Challenge: Implementing equivalent functionality in Ansible
  - Mitigation: Use Ansible's Jinja2 templates or custom filters to achieve the same result

- **Hierarchical data**: The repository uses Hiera with a complex hierarchy:
  - Challenge: Replicating the same level of hierarchy in Ansible
  - Mitigation: Carefully design group_vars, host_vars, and role defaults to maintain the same override capabilities

### Migration Order

1. **Base profile** (low risk, foundation for other components)
   - Migrate site/profile/manifests/base/base.pp to an Ansible role
   - Create corresponding group_vars for NTP and syslog configuration

2. **HAProxy profile** (moderate complexity, fewer dependencies)
   - Migrate modules/profile_haproxy to an Ansible role
   - Create templates for HAProxy configuration
   - Implement firewall rules using Ansible modules

3. **Redis cluster profile** (moderate complexity, PuppetDB challenge)
   - Migrate modules/profile_redis_cluster to an Ansible role
   - Implement alternative to PuppetDB queries for node discovery

4. **Application stack profile** (high complexity, many dependencies)
   - Migrate modules/profile_app_stack to an Ansible role
   - Break down into sub-roles for Python, database, application, service, and monitoring
   - Ensure proper dependency management between components

### Assumptions

1. The target environment will continue to be Ubuntu 24.04 as specified in the Vagrantfile.
2. The application being deployed is a Python application using FastAPI, uvicorn, and gunicorn based on the test fixture.
3. The database backend is PostgreSQL based on the module name and configuration parameters.
4. The current deployment uses a Git repository for application code deployment.
5. The HAProxy configuration includes SSL termination and multiple backends.
6. Redis is used as a caching layer for the application.
7. The current setup uses PuppetDB for node discovery in the Redis cluster.
8. The migration will preserve the current role-based architecture but adapt it to Ansible's role structure.
9. Secrets are currently managed with Hiera eyaml and will need to be migrated to Ansible Vault.
10. The current setup uses systemd for service management.
11. The repository doesn't specify cloud provider integration, so we assume a generic VM deployment target.
12. The current setup includes monitoring integration, but the specific monitoring system is not clearly specified.