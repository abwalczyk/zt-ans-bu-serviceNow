#!/bin/bash
USER=rhel

# su - $USER -c is used a lot because lifecycle scripts always run as root
# but projects and playbooks should be owned by the user that will be using them (e.g. rhel)

# Secrets are only available for the lifecycle of the setup-script
# agent variable set creates variables that are available outside of the setup-script
# the following 2 lines create variables from the env vars that contain low value secrets
# using secrets because they're easy to update in the Instruqt UI. 

agent variable set ADMIN_CONTROLLER_USERNAME $ADMIN_CONTROLLER_USERNAME
agent variable set ADMIN_CONTROLLER_PASSWORD $ADMIN_CONTROLLER_PASSWORD

# vars set using `agent variable set` are available in the environment and can be used in challenge text
agent variable set SANDBOX $INSTRUQT_PARTICIPANT_ID

# Collection used to create correct credential for servicenow on Controller
su - rhel -c 'ansible-galaxy collection install awx.awx'

# create admin project directory
su - rhel -c 'mkdir /tmp/admin_project/'

# allow awx and all others access to project directory
chmod a+x /tmp/admin_project/

# create student project directory
su - rhel -c 'mkdir /home/rhel/servicenow_project'

# allow awx and all others access to project directory
chmod a+x /home/rhel/

# symlink project directories so they can be picked up by controller
su - awx -c 'ln -s /home/rhel/servicenow_project/ /var/lib/awx/projects/'

# create a playbook to customize learner Controller
tee /home/rhel/setup-controller.yml << EOF
---
- name: Configure learner Controller 
  hosts: localhost
  connection: local
  collections:
    - awx.awx
  vars:
    TMM_CONTROLLER_TOKEN: "{{ lookup('env', 'TMM_CONTROLLER_TOKEN') }}"
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
      controller_host: "https://{{ ansible_host }}"
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
      controller_host: "https://{{ ansible_host }}"
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

  - name: modify automation controller token
    awx.awx.credential:
      name: 'Automation Controller'
      organization: Default
      credential_type: "Red Hat Ansible Automation Platform"
      controller_host: "https://{{ ansible_host }}"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        host: https://ansible.demoredhat.com
        oauth_token: "{{ TMM_CONTROLLER_TOKEN }}"

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
        - "Automation Controller"
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

# execute above playbook
echo "execute setup-controller playbook"
su rhel -c '
  export TMM_CONTROLLER_TOKEN=$ANSIBLE_TMM_CONTROLLER_TOKEN &&
  ansible-playbook /home/rhel/setup-controller.yml
'



# populate readme file with environment credentials
su - rhel -c 'tee -a /home/rhel/servicenow_project/readme.md << EOF
# Environment credentials

## Automation Controller
- username: student
- password: learn_ansible

## ServiceNow
- username: $(echo $INSTRUQT_PARTICIPANT_ID)
- password: $(echo $INSTRUQT_PARTICIPANT_ID)

EOF'

# Fixes an issue with podman that produces this error: "Error: error creating tmpdir: mkdir /run/user/1000: permission denied"
su - $USER -c 'loginctl enable-linger $USER'

# Pull the servicenow EE
su - $USER -c 'podman pull quay.io/acme_corp/servicenow-ee:latest'

# Update ansible extension
su - $USER -c 'code-server --install-extension redhat.ansible --force'

# set vscode default settings
su - $USER -c 'cat >/home/$USER/.local/share/code-server/User/settings.json <<EOL
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

EOL
cat /home/$USER/.local/share/code-server/User/settings.json'

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

EOL
cat /home/rhel/servicenow_project/ansible-navigator.yml'

echo "set environment variables to allow for navigator execution of playbooks"
su - $USER -c 'echo "export SN_HOST=https://ansible.service-now.com" >> /home/rhel/.bashrc'
su - $USER -c 'echo "export SN_USERNAME=$INSTRUQT_PARTICIPANT_ID" >> /home/rhel/.bashrc'
su - $USER -c 'echo "export SN_PASSWORD=$INSTRUQT_PARTICIPANT_ID" >> /home/rhel/.bashrc'
echo "remove old navigator rpm install"
su - $USER -c 'sudo dnf -y remove ansible-navigator'
echo "get latest upstream navigator"
# su - $USER -c 'pip3.9 install --user ansible-navigator'

echo "wget playbook for check/solve"
wget -O /tmp/check-jt-run.yml https://raw.githubusercontent.com/cloin/snow-demo-setup/main/track_check_scripts/check-jt-run.yml
wget -O /tmp/check-inventory-sync.yml https://raw.githubusercontent.com/cloin/snow-demo-setup/main/track_check_scripts/check-inventory-sync.yml