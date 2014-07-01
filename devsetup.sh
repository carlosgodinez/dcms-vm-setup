#!/bin/bash
#Fri Jun 27 14:35:18 EDT 2014
#set -x

#
# MANUAL EXECUTION: vmutil myip
#

[ "$#" -eq 1 ] || ( echo "Site Name required. Bye."; exit )

if [ ! `which expect 2>/dev/null` ]; then echo "Install expect -> sudo bash 'yum -y install expect'"; fi

SITE=$1
REL='release-v2.3.1'

echo -e "Host git.timeinc.net\n\tStrictHostKeyChecking no\n\tUserKnownHostsFile /dev/null\n" >> ~/.ssh/config
chmod 600 ~/.ssh/config

rm -rf ~/dcms/$SITE

vmutil sshkeys

echo -e "\n>>> BUILDING LOCAL SITE <<<\n"

echo 'y' | vmutil build $SITE

cd /home/devadmin/dcms/$SITE
git clone git@git.timeinc.net:/dcms/reference

cd ~/dcms/$SITE
git clone git@git.timeinc.net:/dcms/sites/ics-dcms-ioe src 

cd ~/dcms/$SITE/reference
git checkout $REL

cd ~/dcms/$SITE/src
git checkout master

vmutil build $SITE

echo -e "\n>>> DRUPAL INSTANCE BUILD <<<\n"

cat > /tmp/sql <<! 
drop database ${SITE}_local;
create database ${SITE}_local;
!
mysql --verbose -h 127.0.0.1 -u devadmin -pdevadmin < /tmp/sql

cd ~/dcms/$SITE/site
drush -y si standard --account-name=admin --account-pass=admin --db-url=mysql://devadmin:devadmin@localhost/${SITE}_local overwrite

echo -e "\n>>> CONFIGURING SOLR SEARCH FUNCTIONALITY <<<\n"

cd ~/dcms/$SITE

/usr/bin/expect -c'
set timeout 10
#exp_internal 1
#log_user 1
spawn drush en ti_search_config
expect "Do you really want to continue? (y/n):" { send y\r }
expect "Do you want to continue? (y/n):" { send y\r }
expect -re " \\\[(\[0-9]*)\\\] *:  '$SITE'" { set option $expect_out(1,string) }
send $option\r
expect -re " \\\[1\\\]  :  local" { send 1\r }
expect -ex "Response came back"
puts "ti_search_config was enabled successfully"
'

echo -e "\n>>> ENABLING MODULES AND THEMES WITH THE MASTER MODULE <<<\n"

# post deploy steps
phing -f reference/build.xml post-deploy-master 

# rebuild permissions
drush php-eval 'node_access_rebuild();'

# enable themes
cd ~/dcms/$SITE/site
drush en -y ui_editorial ti_editorial_mobile

# webserver permissions
chmod 777 ~/dcms/$SITE/site/sites/default/files

echo -e "\n>>> DONE CONFIGURING DEVELOPER SETUP <<<\n"
