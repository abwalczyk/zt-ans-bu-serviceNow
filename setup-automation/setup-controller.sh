#!/bin/bash

systemctl stop systemd-tmpfiles-setup.service
systemctl disable systemd-tmpfiles-setup.service

# Install collection(s)
ansible-galaxy collection install community.general
ansible-galaxy collection install servicenow.itsm

# Create an inventory file for this environment
tee /tmp/inventory << EOF
[nodes]
node01
node02

[all]
node01
node02

[all:vars]
ansible_user = rhel
ansible_password = ansible123!
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_python_interpreter=/usr/bin/python3

EOF

# creates a playbook to setup environment
tee /tmp/setup.yml << EOF
---
### Automation Controller setup 
###
- name: Setup Controller 
  hosts: localhost
  connection: local
  collections:
    - ansible.controller
  vars:
    GUID: "{{ lookup('env', 'GUID') | default('GUID_NOT_FOUND', true) }}"
    DOMAIN: "{{ lookup('env', 'DOMAIN') | default('DOMAIN_NOT_FOUND', true) }}"
  tasks:

  - name: (EXECUTION) add App machine credential
    ansible.controller.credential:
      name: 'Application Nodes'
      organization: Default
      credential_type: Machine
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        username: rhel
        password: ansible123!

  - name: Add RHEL EE
    ansible.controller.execution_environment:
      name: "Rhel_ee"
      image: quay.io/acme_corp/rhel_90_ee
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add ServiceNow Inventory
    ansible.controller.inventory:
      name: "ServiceNow Inventory"
      description: "Nodes for ServiceNow automation"
      organization: "Default"
      state: present
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add ServiceNow hosts
    ansible.controller.host:
      name: "{{ item }}"
      description: "ServiceNow Automation Nodes"
      inventory: "ServiceNow Inventory"
      state: present
      enabled: true
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
    loop:
      - node01
      - node02
 
  - name: Add ServiceNow group
    ansible.controller.group:
      name: "ServiceNow_Nodes"
      description: "ServiceNow Automation Nodes"
      inventory: "ServiceNow Inventory"
      hosts:
        - node01
        - node02
      variables:
        ansible_user: rhel
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

###############TEMPLATES###############

  - name: Add Rhel Report Template
    ansible.controller.job_template:
      name: "Application Server Report"
      job_type: "run"
      organization: "Default"
      inventory: "ServiceNow Inventory"
      project: "ServiceNow"
      playbook: "playbooks/section01/rhel_report.yml"
      execution_environment: "Rhel_ee"
      credentials:
        - "Application Nodes"
      state: "present"
      survey_enabled: true
      survey_spec:
           {
             "name": "Report Details",
             "description": "Report components needed",
             "spec": [
               {
    	          "type": "multiplechoice",
    	          "question_name": "What data are you looking for ?",
              	"question_description": "Defined data",
              	"variable": "report_type",
                "choices": ["All","Storage Usage","User List","OS Versions"],
                "required": true
               }
             ]
           }
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add OSCAP Setup Template
    ansible.controller.job_template:
      name: "OpenSCAP Report"
      job_type: "run"
      organization: "Default"
      inventory: "ServiceNow Inventory"
      project: "ServiceNow"
      playbook: "playbooks/section01/rhel_compliance_report.yml"
      execution_environment: "Rhel_ee"
      credentials:
        - "Application Nodes"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add RHEL Backup
    ansible.controller.job_template:
      name: "Server Backup - XFS/RHEL"
      job_type: "run"
      organization: "Default"
      inventory: "ServiceNow Inventory"
      project: "ServiceNow"
      playbook: "playbooks/section01/xfs_backup.yml"
      execution_environment: "Rhel_ee"
      credentials:
        - "Application Nodes"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add RHEL Backup Check
    ansible.controller.job_template:
      name: "Check RHEL Backup"
      job_type: "run"
      organization: "Default"
      inventory: "ServiceNow Inventory"
      project: "ServiceNow"
      playbook: "playbooks/section01/check_backups.yml"
      execution_environment: "Rhel_ee"
      credentials:
        - "Application Nodes"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

EOF

# execute above playbook
ANSIBLE_COLLECTIONS_PATH=/tmp/ansible-automation-platform-containerized-setup-bundle-2.5-9-x86_64/collections/:/root/.ansible/collections/ansible_collections/ ansible-playbook -i /tmp/inventory /tmp/setup.yml

# make challenge dir
su - rhel -c 'mkdir /home/rhel/challenge-1'

# Create a playbook for the user to execute which will create a SN incident
tee /home/rhel/servicenow_project/incident-create.yml << EOF
---
- name: Automate SNOW 
  hosts: localhost
  connection: local
  collections:
    - servicenow.itsm

  tasks:

    # Always give your tasks a useful name
    - name: Create incident

      # This task leverages the 'incident' module from the 'itsm' collection 
      # within the 'servicenow' namespace
      servicenow.itsm.incident:

        state: new
        caller: "{{ lookup('env', 'SN_USERNAME') }}"

        # Feel free to modify this line
        short_description: "User created a new incident using Ansible Automation Platform"

        # These fields can also contain different variables from previous workflow steps,
        # environment variables, etc.. Feel free to modify this line
        description: "User {{ lookup('env', 'SN_USERNAME') }} successfully created a new incident!"
        impact: low
        urgency: low
      
      # Register the output of this task for use within subsequent tasks
      register: new_incident

    - set_fact:
        incident_number_cached: "{{ new_incident.record.number }}"
        cacheable: true

    - debug:

        # Use the output of the incident creation task to display the incident number
        msg: "A new incident has been created: {{ new_incident.record.number }}"

EOF

# chown above file
sudo chown rhel:rhel /home/rhel/servicenow_project/incident-create.yml

# Write a new playbook to create a template from above playbook
tee /home/rhel/challenge-1/template-create.yml << EOF
---
- name: Create job template for create-incident
  hosts: localhost
  connection: local
  gather_facts: false
  collections:
    - awx.awx

  tasks:

    - name: Post create-incident job template
      job_template:
        name: "1 - Create incident (incident-create.yml)"
        job_type: "run"
        organization: "Default"
        inventory: "Demo Inventory"
        project: "ServiceNow"
        playbook: "student_project/incident-create.yml"
        execution_environment: "ServiceNow EE"
        use_fact_cache: false
        credentials:
          - "servicenow credential"
        state: "present"
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

EOF

# chown above file
sudo chown rhel:rhel /home/rhel/challenge-1/template-create.yml

# Execute above playbook
su - rhel -c 'ansible-playbook /home/rhel/challenge-1/template-create.yml'

# Grant student account access to challenge job template  
tee /home/rhel/challenge-1/role-update.yml << EOF
---
- name: Create job template for create-incident
  hosts: localhost
  connection: local
  gather_facts: false
  collections:
    - awx.awx

  tasks:

    - name: Post create-incident job template
      role:
        user: student
        role: execute
        job_templates:
          - "1 - Create incident (incident-create.yml)"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

EOF

# chown above file
sudo chown rhel:rhel /home/rhel/challenge-1/role-update.yml

# Execute above playbook
su - rhel -c 'ansible-playbook /home/rhel/challenge-1/role-update.yml'
