#!/bin/bash
USER=rhel
# Install required AWX collection
su - rhel -c 'ansible-galaxy collection install awx.awx'

# Create necessary project directories
su - rhel -c 'mkdir /tmp/admin_project/'
chmod a+x /tmp/admin_project/
su - rhel -c 'mkdir /home/rhel/servicenow_project'
chmod a+x /home/rhel/
su - awx -c 'ln -s /home/rhel/servicenow_project/ /var/lib/awx/projects/'


# Controller configuration playbook (local only)
tee /home/rhel/setup-controller.yml << EOF
---
- name: Configure learner Controller 
  hosts: localhost
  connection: local
  collections:
    - awx.awx
  tasks:

    - name: Add EE to the controller instance
      awx.awx.execution_environment:
        name: "ServiceNow EE"
        image: quay.io/acme_corp/servicenow-ee:latest
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: add snow credential
      awx.awx.credential:
        name: 'servicenow credential'
        organization: Default
        credential_type: servicenow.itsm
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false
        inputs:
          SN_USERNAME: "{{ lookup('env', 'INSTRUQT_PARTICIPANT_ID') }}"
          SN_PASSWORD: "{{ lookup('env', 'INSTRUQT_PARTICIPANT_ID') }}"
          SN_HOST: https://ansible.service-now.com

    - name: add rhel machine credential
      awx.awx.credential:
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
      awx.awx.inventory:
        name: "rhel inventory"
        description: "rhel servers in demo environment"
        organization: "Default"
        state: present
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: add hosts
      awx.awx.host:
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
      awx.awx.group:
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

    - name: Add student project
      awx.awx.project:
        name: "ServiceNow"
        description: "Project containing users ServiceNow playbooks"
        organization: Default
        state: present
        scm_type: git
        scm_url: https://github.com/cloin/instruqt-snow
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: Add admin project
      awx.awx.project:
        name: "ServiceNow - admin"
        description: "Project containing users ServiceNow playbooks for admin use"
        organization: Default
        state: present
        scm_type: git
        scm_url: https://github.com/cloin/instruqt-snow
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: Post SNOW user create job template
      job_template:
        name: "0 - Create SNOW demo user"
        job_type: "run"
        organization: "Default"
        inventory: "Demo Inventory"
        project: "ServiceNow - admin"
        playbook: "admin_project/create-snow-user.yml"
        execution_environment: "ServiceNow EE"
        ask_variables_on_launch: true
        credentials:
          - "servicenow credential"
        state: "present"
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: Launch SNOW user create/destroy job
      awx.awx.job_launch:
        job_template: "0 - Create SNOW demo user"
        extra_vars:
          cleanup: false
        controller_host: https://localhost
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

EOF

# chown above file
sudo chown rhel:rhel /home/rhel/setup-controller.yml

# Run playbook 
echo "execute setup-controller playbook"
su - rhel -c 'ansible-playbook /home/rhel/setup-controller.yml'

# chown above file
sudo chown rhel:rhel /home/rhel/vscode-setup.yml

# Run playbook 
echo "execute vscode-setup playbook"
su - rhel -c 'ansible-playbook /home/rhel/vscode-setup.yml'

# Write credentials to README for learner
su - rhel -c 'tee -a /home/rhel/servicenow_project/readme.md << EOF
# Environment credentials

## ServiceNow
- username: $(echo $INSTRUQT_PARTICIPANT_ID)
- password: $(echo $INSTRUQT_PARTICIPANT_ID)

EOF'

# Enable linger so podman can function for user
su - $USER -c 'loginctl enable-linger $USER'

# Pull EE
su - $USER -c 'podman pull quay.io/acme_corp/servicenow-ee:latest'

{
  "git.ignoreLegacyWarning": true,
  "window.menuBarVisibility": "visible",
  "git.enableSmartCommit": true,
  "workbench.tips.enabled": false,
  "workbench.startupEditor": "readme",
  "telemetry.enableTelemetry": false,
  "search.smartCase": true,
  "git.confirmSync": false,
  "workbench.colorTheme": "Solarized Dark",
  "update.showReleaseNotes": false,
  "update.mode": "none",
  "ansible.ansibleLint.enabled": true,
  "ansible.ansible.useFullyQualifiedCollectionNames": true,
  "redhat.telemetry.enabled": true,
  "markdown.preview.doubleClickToSwitchToEditor": false,
  "files.exclude": {
    "**/.*": true
  },
  "ansible.executionEnvironment.enabled": true,
  "ansible.executionEnvironment.image": "quay.io/acme_corp/servicenow-ee:latest",
  "ansibleServer.trace.server": "verbose",
  "files.associations": {
    "*.yml": "ansible"
  }
}
EOL'

# Write ansible-navigator config
su - $USER -c 'cat >/home/rhel/servicenow_project/ansible-navigator.yml <<EOL
---
ansible-navigator:
  execution-environment:
    enabled: true
    container-engine: podman
    image: quay.io/acme_corp/servicenow-ee:latest
    pull:
      policy: never
    environment-variables:
      pass:
        - SN_HOST
        - SN_USERNAME
        - SN_PASSWORD
        - INSTRUQT_PARTICIPANT_ID
  playbook-artifact:
    enable: true
    save-as: "{playbook_dir}/artifacts/{playbook_name}-artifact-{time_stamp}.json"
  logging:
    append: true
    file: 'artifacts/ansible-navigator.log'
    level: warning
  editor:
    command: code-server {filename}
    console: false
EOL'

# Set environment variables in bashrc for navigator
su - $USER -c 'echo "export SN_HOST=https://ansible.service-now.com" >> /home/rhel/.bashrc'
su - $USER -c 'echo "export SN_USERNAME=$INSTRUQT_PARTICIPANT_ID" >> /home/rhel/.bashrc'
su - $USER -c 'echo "export SN_PASSWORD=$INSTRUQT_PARTICIPANT_ID" >> /home/rhel/.bashrc'

# Clean up old navigator
su - $USER -c 'sudo dnf -y remove ansible-navigator'

# Download checker playbooks
wget -O /tmp/check-jt-run.yml https://raw.githubusercontent.com/cloin/snow-demo-setup/main/track_check_scripts/check-jt-run.yml
wget -O /tmp/check-inventory-sync.yml https://raw.githubusercontent.com/cloin/snow-demo-setup/main/track_check_scripts/check-inventory-sync.yml
