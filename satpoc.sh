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


logline()
{
  # Prints a message to stdout and to a log file
  # The log file is defined by the $LOG global variable
  echo "$1" | tee -a "$LOG"
}




start_time()
{
  clear
  logline "# Starting installation - $(date)"
}

attach_ent()
{
  logline "# Attaching pool"
  # Collect here the subs availabe to Satellite.
  subscription-manager attach --pool=xxxxxxxxxxxxxxxxxxxxxxxxx | tee -a $LOG
}

repos()
{
  logline "# Enabling repos"
  # Repos for rhel7
  subscription-manager repos --disable "*" | tee -a $LOG
  subscription-manager repos --enable rhel-7-server-rpms --enable rhel-server-rhscl-7-rpms --enable rhel-7-server-satellite-6.1-rpms | tee -a $LOG
}

conf_base()
{
  logline "# Basic Configurations"
  logline "######################"

  #echo "# Stopping Firewall" | tee -a $LOG
  logline "# Setting Firewall Rules"
  # Firewall
  firewall-cmd --add-port="53/udp" --add-port="53/tcp" \
    --add-port="67/udp" --add-port="68/udp" \
    --add-port="69/udp" --add-port="80/tcp" \
    --add-port="443/tcp" --add-port="5647/tcp" \
    --add-port="8140/tcp" \
  && firewall-cmd --permanent --add-port="53/udp" --add-port="53/tcp" \
    --add-port="67/udp" --add-port="68/udp" \
    --add-port="69/udp" --add-port="80/tcp" \
    --add-port="443/tcp" --add-port="5647/tcp" \
    --add-port="8140/tcp"
  #systemctl stop firewalld
  #systemctl disable firewalld
  

  logline "# Disabling Selinux"
  # Selinux
  setenforce 0
  sed -i -e 's/=enforcing/=permissive/g' /etc/selinux/config 


  logline "# Configuring hosts"
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
  logline "# Updating the OS"
  logline "######################"
  yum update -y
}

katello_install()
{
  logline "# Installing the Katello"
  logline "######################"
  yum install katello -y | tee -a $LOG
  #katello-installer --foreman-admin-username $ADMIN_USER --foreman-admin-password $PASSWORD_ADMIN | tee -a $LOG
  katello-installer --foreman-initial-organization $ORGANIZATION --foreman-initial-location $LOCATION --foreman-admin-username $ADMIN_USER --foreman-admin-password $PASSWORD_ADMIN | tee -a $LOG
}

hammer_auth()
{
cat << HAMMEREND > /root/cli_config.yml
:foreman:
    :host: 'https://localhost/'
    :username: '$ADMIN_USER'
    :password: '$PASSWORD_ADMIN'
HAMMEREND
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
  logline "# Finishing the installation - $(date)"
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
