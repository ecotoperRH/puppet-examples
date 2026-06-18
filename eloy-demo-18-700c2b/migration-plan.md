# MIGRATION FROM PUPPET TO ANSIBLE

## Executive Summary

This repository contains a Puppet-based infrastructure configuration for a multi-tier application stack consisting of HAProxy load balancers, Python application servers with PostgreSQL databases, and Redis cache clusters. The migration to Ansible will require converting Puppet modules, classes, and Hiera data structures to Ansible roles, playbooks, and variable files.

**Estimated Timeline:**
- Analysis and Planning: 1 week
- Core Module Migration: 3-4 weeks
- Testing and Validation: 2 weeks
- Documentation and Knowledge Transfer: 1 week
- Total: 7-8 weeks

**Complexity Assessment:** Medium to High
- Multiple interconnected components with strict dependency chains
- Secret management with Hiera eyaml
- PuppetDB queries for node discovery that need Ansible alternatives

## Module Migration Plan

This repository contains Puppet modules that need individual migration planning:

### MODULE INVENTORY

- **profile_app_stack**:
    - Description: Python application stack with PostgreSQL database and systemd service management
    - Path: modules/profile_app_stack
    - Technology: Puppet
    - Key Features: Python app deployment from Git, PostgreSQL database configuration, systemd service management, application monitoring

- **profile_haproxy**:
    - Description: HAProxy load balancer with multi-backend support, SSL termination, and statistics interface
    - Path: modules/profile_haproxy
    - Technology: Puppet
    - Key Features: Backend server configuration, SSL certificate management, firewall rules, statistics dashboard

- **profile_redis_cluster**:
    - Description: Redis cluster configuration with node discovery via PuppetDB
    - Path: modules/profile_redis_cluster
    - Technology: Puppet
    - Key Features: Redis server configuration, memory management, password authentication, node discovery

- **base_profile**:
    - Description: Common base configuration for all nodes including NTP, syslog, and utility packages
    - Path: site/profile/manifests/base
    - Technology: Puppet
    - Key Features: OS-level configuration, service management, package installation

### Infrastructure Files

- `Puppetfile`: Defines external module dependencies including puppetlabs-stdlib, puppetlabs-concat, puppetlabs-firewall, puppetlabs-vcsrepo, puppet-redis, and puppetlabs-apt
- `hiera.yaml`: Defines the Hiera hierarchy with encrypted node-specific data, environment-specific data, and common defaults
- `environment.conf`: Configures the Puppet environment module path
- `data/common.yaml`: Common configuration values for all environments
- `data/environment/*.yaml`: Environment-specific configuration overrides
- `Vagrantfile`: Defines a development environment using Ubuntu 24.04 with libvirt provider
- `vagrant-provision.sh`: Provisions the Vagrant VM with Puppet and required modules
- `test/site.pp`: Test manifest that includes all profiles and creates a test Git repository
- `test/data/common.yaml`: Test data overrides for development environment

### Target Details

Based on the source configuration files:

- **Operating System**: Ubuntu 24.04 (Noble Numbat) as specified in the Vagrantfile
- **Virtual Machine Technology**: libvirt (KVM) as configured in the Vagrantfile
- **Cloud Platform**: Not specified, appears to be targeting on-premises or generic cloud VMs

## Migration Approach

### Key Dependencies to Address

- **puppetlabs-stdlib (9.7.0)**: Replace with Ansible built-in filters and modules
- **puppetlabs-concat (9.0.2)**: Replace with Ansible template module and blockinfile/lineinfile modules
- **puppetlabs-firewall (8.1.3)**: Replace with Ansible firewalld or iptables modules
- **puppetlabs-vcsrepo (6.1.0)**: Replace with Ansible git module
- **puppet-redis (11.0.0)**: Replace with Ansible community.general.redis module or custom Redis role
- **puppetlabs-apt (9.4.0)**: Replace with Ansible apt module

### Security Considerations

- **Hiera eyaml encryption**: Migrate to Ansible Vault for secrets management
  - Migration approach: Identify all encrypted values in Hiera eyaml files and convert them to Ansible Vault variables
  
- **Vault/secrets management**:
  - profile_app_stack: 3 credentials detected (db_password, secret_key, potentially app_user password)
  - profile_haproxy: 1 credential detected (stats_password)
  - profile_redis_cluster: 1 credential detected (redis_password)
  
- **SSL/TLS configuration**:
  - HAProxy SSL certificate and key paths need to be managed securely
  - SSL ciphers and minimum version settings need to be preserved

- **Database credentials**:
  - PostgreSQL database credentials in profile_app_stack need secure handling

### Technical Challenges

- **PuppetDB node discovery**: The Redis cluster uses PuppetDB queries to discover other Redis nodes
  - Mitigation: Replace with Ansible inventory groups or dynamic inventory plugins
  
- **Strict dependency chains**: The application stack has explicit ordering requirements
  - Mitigation: Use Ansible handlers, meta tasks, and proper role dependencies to maintain execution order
  
- **Custom Puppet functions**: The profile_app_stack uses a custom function to build database URLs
  - Mitigation: Create equivalent Jinja2 templates or custom Ansible filters
  
- **Hiera data hierarchy**: Complex multi-level hierarchy with environment-specific overrides
  - Mitigation: Use Ansible group_vars and host_vars with proper directory structure to replicate hierarchy

### Migration Order

1. **Base Profile** (Priority 1, low risk): Common OS-level configurations
   - Create base Ansible role for NTP, syslog, and utility packages
   
2. **HAProxy Profile** (Priority 2, moderate complexity):
   - Create HAProxy role with templates for configuration files
   - Implement firewall rules using Ansible modules
   
3. **Redis Cluster Profile** (Priority 3, moderate complexity):
   - Create Redis role with configuration templates
   - Implement alternative to PuppetDB node discovery
   
4. **Application Stack Profile** (Priority 4, high complexity):
   - Create roles for Python application deployment
   - Create roles for PostgreSQL database configuration
   - Implement systemd service management
   - Ensure proper dependency ordering

### Assumptions

1. The target environment will continue to be Ubuntu 24.04 as specified in the Vagrantfile
2. The application architecture will remain the same (HAProxy → Python App → PostgreSQL + Redis)
3. The current security model using encrypted passwords will be maintained
4. The strict dependency chain in the application stack is necessary for proper operation
5. The test environment setup with Vagrant will be replaced with Ansible-based testing
6. The PuppetDB query functionality for Redis cluster node discovery needs an equivalent in Ansible
7. The custom Puppet functions will need to be reimplemented as Ansible filters or templates
8. The current directory structure and naming conventions will be adapted to Ansible best practices
9. The Hiera data hierarchy will be mapped to Ansible variable precedence
10. The current test fixtures will be converted to Ansible molecule tests or equivalent