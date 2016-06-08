#!/bin/bash


#######
# Vars
CLI_CONF_HAMMER="/root/cli_config.yml"

ORGANIZATION="ACME"
LOCATION="CITY"
ADMIN_USER="admin"
PASSWORD_ADMIN="redhat"

REPOS=""
CV="cv_rhel72_base"
CCV="ccv_rhel7_base_acme"
LIFECYCLE=""
MANIFEST=""

#######


####################
LOG="/var/log/satinstallation.log"


start_time()
{
  clear
  echo "# Starting installation - $(date)" | tee -a $LOG
}

attach_ent()
{
  echo "# Attaching pool" | tee -a $LOG
  # Collect here the subs availabe to Satellite.
  subscription-manager attach --pool=xxxxxxxxxxxxxxxxxxxxxxxxx | tee -a $LOG
}

repos()
{
  echo "# Enabling repos" | tee -a $LOG
  # Repos for rhel7
  subscription-manager repos --disable "*" | tee -a $LOG
  subscription-manager repos --enable rhel-7-server-rpms --enable rhel-server-rhscl-7-rpms --enable rhel-7-server-satellite-6.1-rpms | tee -a $LOG
}

conf_base()
{
  echo "# Basic Configurations" | tee -a $LOG
  echo "######################" | tee -a $LOG

  echo "# Stoping Firewall" | tee -a $LOG
  echo "# Stopping Firewall" | tee -a $LOG
  # Firewall
  systemctl stop firewalld
  systemctl disable firewalld
  

  echo "# Disabling Selinux" | tee -a $LOG
  # Selinux
  setenforce 0
  sed -i -e 's/=enforcing/=permissive/g' /etc/selinux/config 


  echo "# Configuring hosts" | tee -a $LOG
  # Hostname
  IP=$(ip a|grep "inet "|grep -v 127|awk '{print $2}'|cut -d/ -f1)
  HOSTNAME_FQDN=$(hostname)
  HOSTNAME_ALIAS=$(hostname -s)

  TestHosts=$(grep $HOSTNAME_FQDN /etc/hosts|wc -l)
  if [ $TestHosts -eq 0 ]; then
    echo "$IP $HOSTNAME_FQDN $HOSTNAME_ALIAS" >>/etc/hosts
  fi

  # Installing vim
  yum install vim -y

}

update_system()
{
  echo "# Updating the OS" | tee -a $LOG
  echo "######################" | tee -a $LOG
  yum update -y
}

katello_install()
{
  echo "# Installing the Katello" | tee -a $LOG
  echo "######################" | tee -a $LOG
  yum install katello -y | tee -a $LOG
  #katello-installer --foreman-admin-username $ADMIN_USER --foreman-admin-password $PASSWORD_ADMIN | tee -a $LOG
  katello-installer --foreman-initial-organization $ORGANIZATION --foreman-initial-location $LOCATION --foreman-admin-username $ADMIN_USER --foreman-admin-password $PASSWORD_ADMIN | tee -a $LOG
}

hammer_auth()
{
echo "
:foreman:
    :host: 'https://localhost/'
    :username: '$ADMIN_USER'
    :password: '$PASSWORD_ADMIN'
" > /root/cli_config.yml
}

hammer_general()
{

  hammerFull="hammer -c $CLI_CONF_HAMMER"

  # Importing manifest
  $hammerFull subscription upload --file /root/manifest.zip --organization $ORGANIZATION


  # Enable the repos
  # =====
  $hammerFull repository-set enable  --organization "$ORGANIZATION" \
    --product "Red Hat Enterprise Linux Server" \
    --name "Red Hat Enterprise Linux 7 Server (Kickstart)" \
    --releasever "7.2" --basearch "x86_64"

  $hammerFull repository-set enable  --organization "$ORGANIZATION" \
    --product "Red Hat Enterprise Linux Server" \
    --name "Red Hat Enterprise Linux 7 Server (RPMs)" \
    --releasever "7.2" --basearch "x86_64"

  $hammerFull repository-set enable  --organization "$ORGANIZATION"  \
    --product "Red Hat Enterprise Linux Server"  \
    --name "Red Hat Satellite Tools 6.1 (for RHEL 7 Server) (RPMs)" \
    --basearch "x86_64"
  # =====


  # Start Sync
  # =====
  listIdStartSync=$(hammer -c /root/cli_config.yml repository list --organization ACME|awk '{print $1}'|grep -E '(^[0-9])')
  listIdStartSync=$(hammer -c /root/cli_config.yml repository list --organization $ORGANIZATION|awk '{print $1}'|grep -E '(^[0-9])')

  for b in $listIdStartSync
  do
    $hammerFull repository synchronize --id $b --organization $ORGANIZATION --async
  done
  # =====
  

  # LifeCycle
  $hammerFull lifecycle-environment create --label dev-rhel72 --name dev-rhel72 --organization $ORGANIZATION --prior Library 
  $hammerFull lifecycle-environment create --label qa-rhel72 --name qa-rhel72 --organization $ORGANIZATION --prior dev-rhel72 
  $hammerFull lifecycle-environment create --label prod-rhel72 --name prod-rhel72 --organization $ORGANIZATION --prior qa-rhel72
 
}





stop_time()
{
  echo "# Finishing the installation - $(date)" | tee -a $LOG
}




# Main
start_time
attach_ent
repos
conf_base
update_system
katello_install
hammer_auth
hammer_general

stop_time
