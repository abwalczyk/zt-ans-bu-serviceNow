#!/bin/bash

# Create a playbook for the user to execute which will create a SN incident
tee /tmp/problem-attach.yml << EOF
---
- name: Automate SNOW 
  hosts: localhost
  connection: local
  collections:
    - servicenow.itsm
    
  vars:
    demo_username: "{{ lookup('env', 'SN_USERNAME') }}"
    incident_list: []

  tasks:
  - name: find user created incidents
      servicenow.itsm.incident_info:
      query:
          - sys_created_by: LIKE {{ demo_username }}
          active: = true
      register: incidents

  - name: query incident number and creation time 
      set_fact:
      incident_list: '{{ incident_list + [{"number": item.number, "opened_at": item.opened_at}] }}'
      loop: "{{ incidents.records }}"
      when: incidents

  - name: Create a problem from incident
      servicenow.itsm.problem:
      short_description: "The website is completely down!!!!"
      description: "{{ lookup('env', 'SN_USERNAME') }} created a new problem"
      register: problem

  - name: Assign a problem to a user for assessment
      servicenow.itsm.problem:
      number: "{{ problem.record.number }}"
      state: new
      assigned_to: "{{ lookup('env', 'SN_USERNAME') }}"

  - name: Update incident status now that problem has been created
      servicenow.itsm.api:
        table: incident
        method: patch
        sys_id: "{{ item.sys_id }}"
        body:
          state: "2"
          problem_id: "{{ problem.record.sys_id }}"
      loop: "{{ incidents.records }}"

  - debug:
      msg: "A new problem has been created {{ problem.record.number }}"

EOF

# chown above file
chown rhel:rhel /tmp/problem-attach.yml

# Write a new playbook to create a template from above playbook
tee /tmp/template-create-problem.yml << EOF
---
- name: Create job template for problem-attach
  hosts: localhost
  connection: local
  gather_facts: false
  collections:
    - ansible.controller

  tasks:

  - name: Post create-incident job template
    job_template:
      name: "2 - Attach problem (problem-attach.yml)"
      job_type: "run"
      organization: "Default"
      inventory: "Demo Inventory"
      project: "ServiceNow - admin"
      playbook: "student_project/problem-attach.yml"
      execution_environment: "ServiceNow EE"
      credentials:
        - "ServiceNow Credential"
      state: "present"
      ask_variables_on_launch: false
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

EOF

# chown above file
chown rhel:rhel /tmp/template-create-problem.yml

# Execute above playbook
ANSIBLE_COLLECTIONS_PATH="/root/.ansible/collections/ansible_collections/" \
ansible-playbook -i /tmp/inventory /tmp/template-create-problem.yml
