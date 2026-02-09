#!/bin/bash

#Make sure collection is installed
ansible-galaxy collection install ansible.controller ansible.platform servicenow.itsm

# Create an inventory file for this environment
tee /tmp/inventory << EOF
[nodes]
node01
node02

[all]
node01
node02
aap

[all:vars]
ansible_user = rhel
ansible_password = ansible123!
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_python_interpreter=/usr/bin/python3

EOF

sudo chown rhel:rhel /tmp/inventory


# Controller configuration playbook (local only)
tee /tmp/setup-controller.yml << EOF
---
- name: Configure learner Controller 
  hosts: localhost
  connection: local
  collections:
    - ansible.controller
  vars:
    #SANDBOX_ID: "{{ lookup('env', '_SANDBOX_ID') | default('SANDBOX_ID_NOT_FOUND', true) }}"
    SN_HOST_VAR: "{{ '{{' }} SN_HOST {{ '}}' }}"
    SN_USER_VAR: "{{ '{{' }} SN_USERNAME {{ '}}' }}"
    SN_PASSWORD_VAR: "{{ '{{' }} SN_PASSWORD {{ '}}' }}"

  tasks:
  - name: Add EE to the controller instance
    ansible.controller.execution_environment:
      name: "RHEL EE"
      image: quay.io/acme_corp/rhel_90_ee:latest
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
  
  - name: Add SNOW EE to the controller instance
    ansible.controller.execution_environment:
      name: "ServiceNow EE"
      image: quay.io/acme_corp/servicenow-ee:latest
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: add ServiceNow Type
    ansible.controller.credential_type:
      name: 'ServiceNow Credential'
      description: ServiceNow Credential
      kind: cloud
      inputs: 
        fields:
          - id: SN_HOST
            type: string
            label: SNOW Instance
          - id: SN_USERNAME
            type: string
            label: SNOW Username
          - id: SN_PASSWORD
            type: string
            secret: true
            label: SNOW Password
        required:
          - SN_HOST
          - SN_USERNAME
          - SN_PASSWORD
      injectors:
          env:
            SN_HOST: "{{ SN_HOST_VAR }}"
            SN_USERNAME: "{{ SN_USER_VAR }}"
            SN_PASSWORD: "{{ SN_PASSWORD_VAR }}"
      state: present
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: add snow credential
    ansible.controller.credential:
      name: 'ServiceNow Credential'
      organization: Default
      credential_type: 'ServiceNow Credential'
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        SN_USERNAME: aap-roadshow
        SN_PASSWORD: Ans1ble123!
        SN_HOST: https://ansible.service-now.com

  - name: add rhel machine credential
    ansible.controller.credential:
      name: 'rhel credential'
      organization: Default
      credential_type: Machine
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        username: rhel
        password: ansible123!

  - name: add rhel inventory
    ansible.controller.inventory:
      name: "rhel inventory"
      description: "rhel servers in demo environment"
      organization: "Default"
      state: present
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: add hosts
    ansible.controller.host:
      name: "{{ item }}"
      description: "rhel host"
      inventory: "rhel inventory"
      state: present
      enabled: true
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
    loop:
      - node01
      - node02

  - name: Add group
    ansible.controller.group:
      name: nodes
      description: "rhel host group"
      inventory: rhel inventory
      hosts:
        - node01
        - node02
      variables:
        ansible_user: rhel
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
  - name: Add admin project
    ansible.controller.project:
      name: "ServiceNow - admin"
      description: "Project containing users ServiceNow playbooks for admin use"
      organization: Default
      state: present
      scm_type: git
      scm_url: https://github.com/abwalczyk/instruqt-snow
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
  - name: Delete native job template
    ansible.controller.job_template:
      name: "Demo Job Template"
      organization: Default
      state: "absent"
      controller_username: admin
      controller_password: ansible123!
      controller_host: "https://localhost"
      validate_certs: false

EOF

# chown above file
sudo chown rhel:rhel /tmp/setup-controller.yml
sudo chown rhel:rhel /tmp/inventory
sudo chown -R rhel:rhel /root/.ansible/collections

sleep 20

# Run the playbook with the correct collections path environment variable and only existing paths
ANSIBLE_COLLECTIONS_PATH="/root/.ansible/collections/ansible_collections/" \
ansible-playbook -i /tmp/inventory /tmp/setup-controller.yml