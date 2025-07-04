#!/bin/bash

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