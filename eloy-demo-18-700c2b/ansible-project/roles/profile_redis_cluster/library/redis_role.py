#!/usr/bin/python
# -*- coding: utf-8 -*-

# Copyright: (c) 2023, Your Name <your.email@example.org>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import absolute_import, division, print_function
__metaclass__ = type

DOCUMENTATION = r'''
---
module: redis_role
short_description: Determine Redis node role (primary or replica)
description:
    - This module checks the Redis configuration to determine if the node is a primary or replica.
    - It examines the configuration file for the presence of the 'replicaof' directive.
options:
    config_file:
        description:
            - Path to the Redis configuration file to check.
        default: /etc/redis/conf.d/replica.conf
        type: str
author:
    - Your Name (@yourgithub)
'''

EXAMPLES = r'''
- name: Get Redis role
  redis_role:
  register: redis_role_result

- name: Display Redis role
  debug:
    msg: "This Redis node is a {{ redis_role_result.role }}"
'''

RETURN = r'''
role:
    description: The role of the Redis node (primary or replica)
    type: str
    returned: always
    sample: primary
'''

import os
from ansible.module_utils.basic import AnsibleModule


def main():
    module = AnsibleModule(
        argument_spec=dict(
            config_file=dict(type='str', default='/etc/redis/conf.d/replica.conf'),
        ),
        supports_check_mode=True
    )

    config_file = module.params['config_file']
    
    if os.path.exists(config_file):
        try:
            with open(config_file, 'r') as f:
                content = f.read()
                if 'replicaof' in content:
                    role = 'replica'
                else:
                    role = 'primary'
        except IOError as e:
            module.fail_json(msg=f"Error reading config file: {str(e)}")
    else:
        # If config file doesn't exist, assume it's a primary
        role = 'primary'  # Default to primary if config file doesn't exist
    
    module.exit_json(
        changed=False,
        role=role
    )


if __name__ == '__main__':
    main()