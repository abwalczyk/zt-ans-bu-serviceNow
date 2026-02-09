#!/bin/bash

# Create a playbook for the user to execute which will create a SN incident
tee /tmp/create-inventory-project.yml << EOF
---
- name: Configure SCM project 
  hosts: localhost
  connection: local
  collections:
    - ansible.controller

  tasks:

  - name: Add SCM project
    ansible.controller.project:
      name: "ServiceNow inventory project"
      description: "Project that contains a now.yml to be sourced by an inventory"
      organization: Default
      state: present
      scm_type: git
      scm_url: https://github.com/abwalczyk/instruqt-snow
      scm_update_on_launch: true
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

EOF

# chown above file
su chown rhel:rhel /tmp/create-inventory-project.yml

# execute above playbook
# Run the playbook with the correct collections path environment variable and only existing paths
ANSIBLE_COLLECTIONS_PATH="/root/.ansible/collections/ansible_collections/" \
ansible-playbook -i /tmp/inventory /tmp/create-inventory-project.yml



# Write a new playbook to create an inventory sourcing project above
tee /tmp/create-inventory.yml << EOF
---
- name: Configure servicenow inventory
  hosts: localhost
  connection: local
  gather_facts: false
  collections:
    - ansible.controller

  tasks:

  - name: Add servicenow inventory
    ansible.controller.inventory:
      name: "ServiceNow inventory"
      description: "Servers added to ServiceNow CMDB"
      organization: "Default"
      state: present
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add an inventory source
    inventory_source:
      name: "inventory-source"
      description: "now.yml from project 'ServiceNow inventory project'"
      inventory: "ServiceNow inventory"
      credential: "ServiceNow Credential"
      source: scm
      source_project: "ServiceNow inventory project"
      source_path: now.yml
      overwrite: true
      update_on_launch: true
      organization: Default
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

EOF

# chown above file
sudo chown rhel:rhel /tmp/create-inventory.yml

# Run the playbook with the correct collections path environment variable and only existing paths
ANSIBLE_COLLECTIONS_PATH="/root/.ansible/collections/ansible_collections/" \
ansible-playbook -i /tmp/inventory /tmp/create-inventory.yml
