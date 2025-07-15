#!/bin/bash
USER=rhel

#Make sure collection is installed
ansible-galaxy collection install ansible.controller


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
    SANDBOX_ID: "{{ lookup('env', '_SANDBOX_ID') | default('SANDBOX_ID_NOT_FOUND', true) }}"
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
    
    - name: Add EE to the controller instance
      ansible.controller.execution_environment:
        name: "ServiceNow EE"
        image: quay.io/acme_corp/servicenow-ee:latest
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: add ServiceNow Type
      ansible.controller.credential_type:
        name: ServiceNow
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
        name: 'ServiceNow'
        organization: Default
        credential_type: ServiceNow
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
        - node1
        - node2

    - name: Add group
      ansible.controller.group:
        name: nodes
        description: "rhel host group"
        inventory: rhel inventory
        hosts:
          - node1
          - node2
        variables:
          ansible_user: rhel
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

EOF

# chown above file
sudo chown rhel:rhel /tmp/setup-controller.yml
sudo chown rhel:rhel /tmp/inventory

sleep 20

ANSIBLE_COLLECTIONS_PATH=/tmp/ansible-automation-platform-containerized-setup-bundle-2.5-9-x86_64/collections/:/root/.ansible/collections/ansible_collections/ ansible-playbook -i /tmp/inventory /tmp/setup-controller.yml