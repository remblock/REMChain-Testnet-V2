#!/usr/bin/env bash

#****************************************************************************************************#
#                                           INSTALL-1.SH                                             #
#****************************************************************************************************#

function pause(){
   read -p "$*"
}

#-----------------------------------------------------------------------------------------------------
# UPDATING AND UPGRADING PACKAGE DATABASE 
#-----------------------------------------------------------------------------------------------------

sudo -S apt update && sudo -S apt upgrade
echo " "
echo "SET YOUR NEW ROOT PASSWORD:"
passwd root

#-----------------------------------------------------------------------------------------------------
# CHANGING DEFAULT SSH PORT NUMBER
#-----------------------------------------------------------------------------------------------------

echo " "
echo "CHOOSE A RANDOM 5 DIGIT PORT NUMBER:"
read -n 5 portnumber
sudo -S sed -i "/^#Port 22/s/#Port 22/Port $portnumber/" /etc/ssh/sshd_config && sed -i '/^PermitRootLogin/s/yes/no/' /etc/ssh/sshd_config

#-----------------------------------------------------------------------------------------------------
# INSTALLING UNCOMPLICATED FIREWALL
#-----------------------------------------------------------------------------------------------------

sudo -S apt-get install ufw -y
sudo -S ufw allow ssh/tcp
sudo -S ufw limit ssh/tcp
sudo -S ufw allow $portnumber/tcp
sudo -S ufw allow 8888/tcp
sudo -S ufw allow 9877/tcp
sudo -S ufw logging on
sudo -S ufw enable

#-----------------------------------------------------------------------------------------------------
# INSTALLING FAIL2BAN
#-----------------------------------------------------------------------------------------------------

sudo -S apt -y install fail2ban
sudo -S systemctl enable fail2ban
sudo -S systemctl start fail2ban
sudo -S service sshd restart

#-----------------------------------------------------------------------------------------------------
# CREATING NEW USER ACCOUNT
#-----------------------------------------------------------------------------------------------------

echo " "
echo " "
echo "CREATING YOUR NEW USER ACCOUNT"
echo "SET YOUR USERNAME:"
read username
sudo adduser $username
sudo usermod -aG sudo $username

#-----------------------------------------------------------------------------------------------------
# CREATING SSH KEYS FOR SERVER
#-----------------------------------------------------------------------------------------------------

echo " "
echo "GENERATING YOUR SSH KEYS:"
echo " "
su $username -c ssh-keygen
sudo sed -i ‘s/PasswordAuthentication yes/PasswordAuthentication no/’ /etc/ssh/sshd_config
sudo systemctl restart ssh
echo " "
echo "TAKE NOTE OF YOUR SSH PRIVATE KEY:"
echo " "
sudo cat /home/$username/.ssh/id_rsa
echo " "
pause 'Press [Enter] key to continue...'
echo " "

#-----------------------------------------------------------------------------------------------------
# COPYING SSH KEY OVER TO THE LOCAL HOST  
#-----------------------------------------------------------------------------------------------------

ssh_copy() {
sudo apt-get install sshpass -y
echo $SSH_CLIENT | awk '{ print $1}'
ip_ssh=$(echo $SSH_CLIENT | awk '{ print $1}')
echo "OK LET'S START COPYING OVER YOUR KEY FILES"
echo " "
read -p "PLEASE ENTER YOUR LOCAL HOST PORT: " ssh_host_port
echo " "
read -p "PLEASE ENTER YOUR LOCAL HOST USERNAME: " ssh_host_user
echo " "
read -p "PLEASE ENTER YOUR LOCAL HOST PASSWORD: " ssh_host_password
echo " "
sudo sshpass -p $ssh_host_password ssh $ssh_host_user@$ip_ssh -p $ssh_host_port "mkdir -p ~/home/$ssh_host_user/.ssh"
sudo sshpass -p $ssh_host_password ssh-copy-id -i ~/home/$username/.ssh/id_rsa $ssh_host_user@$ip_ssh -p $ssh_host_port
echo " "
echo "[********************** DONE ************************]"
}
read -p "DO YOU WANT TO TRANSFER YOUR KEYS TO YOUR LOCAL HOST THROUGH SSH? [y/n]: " yn
  case $yn in
       y|Y ) ssh_copy
	     break;;
       n|N ) printf "\n[********************** DONE ************************]\n\n";;
       * )   echo "PLEASE ANSWER USING [y/n] or [Y/N]";;
   esac

#-----------------------------------------------------------------------------------------------------
# INSTALLING CANONICAL LIVEPATCH SERVICE
#-----------------------------------------------------------------------------------------------------

sudo snap install canonical-livepatch

#-----------------------------------------------------------------------------------------------------
# INSTALLING REM PROTOCOL BINARIES
#-----------------------------------------------------------------------------------------------------

wget https://github.com/Remmeauth/remprotocol/releases/download/0.2.1/remprotocol_0.2.1-1_amd64.deb && sudo apt install ./remprotocol_0.2.1-1_amd64.deb

#-----------------------------------------------------------------------------------------------------
# BOOTING REMNODE AND WALLET
#-----------------------------------------------------------------------------------------------------

wget https://testchain.remme.io/genesis.json

#-----------------------------------------------------------------------------------------------------
# CREATING A CONFIG AND DATA DIRECTORIES
#-----------------------------------------------------------------------------------------------------

mkdir data && mkdir config

#-----------------------------------------------------------------------------------------------------
# CONFIGURATION FILE (CONFIG/CONFIG.INI)
#-----------------------------------------------------------------------------------------------------

echo -e "plugin = eosio::chain_api_plugin\n\nplugin = eosio::net_api_plugin\n\nhttp-server-address = 0.0.0.0:8888\n\np2p-listen-endpoint = 0.0.0.0:9876\n\n# https://remme.io\n\np2p-peer-address = p2p.testchain.remme.io:2087\n\n# https://eon.llc\n\np2p-peer-address = 3.227.137.101:9877\n\n# https://remblock.pro\n\np2p-peer-address = 95.179.237.207:9877\n\np2p-peer-address = 45.77.59.14:9877\n\np2p-peer-address = 45.77.227.198:9877\n\np2p-peer-address = 45.77.56.243:9877\n\n# https://testnet.geordier.co.uk\n\np2p-peer-address = 45.76.132.248:9877\n\nverbose-http-errors = true\n\nchain-state-db-size-mb = 100480\n\nreversible-blocks-db-size-mb = 10480" > ./config/config.ini

#-----------------------------------------------------------------------------------------------------
# THE INITIAL RUN OF THE REMNODE
#-----------------------------------------------------------------------------------------------------

nohup remnode --config-dir ./config/ --data-dir ./data/ --delete-all-blocks --genesis-json genesis.json  2>&1 | tee remnode_sync.log &>/dev/null &

t1=""
t2=""
to_date=$(date '+%Y-%m-%d')
tail -n 3 -f  remnode_sync.log |  while read LINE0
do 
t1=$(echo $LINE0 | cut -d'@' -f2 )
t2=$(echo $t1 | cut -d'T' -f1)
#echo $LINE0 
if [[ $to_date == $t2 ]]; then
ps -ef | grep remnode | grep -v grep | awk '{print $2}' | xargs kill
fi 
echo "fetching blocks....."
done

#-----------------------------------------------------------------------------------------------------
# RUNNING REMNODE IN THE BACKGROUND
#-----------------------------------------------------------------------------------------------------

remnode --config-dir ./config/ --data-dir ./data/ >> remnode.log 2>&1 &
sleep 1

#-----------------------------------------------------------------------------------------------------
# RUNNING THE WALLET DAEMON
#-----------------------------------------------------------------------------------------------------

remvault &
sleep 2

#-----------------------------------------------------------------------------------------------------
# CREATING THE REMCLI WALLET
#-----------------------------------------------------------------------------------------------------

remcli wallet create --file walletpass
walletpass=$(cat walletpass)
echo $walletpass > producerwalletpass.txt

#-----------------------------------------------------------------------------------------------------
# ASKING USER FOR REM ACCOUNT DETAILS
#-----------------------------------------------------------------------------------------------------

echo " "
read -p "ENTER YOUR DOMAIN ADDRESS: " domain
echo $domain > domain.txt
echo " "
read -p "ENTER YOUR OWNER PUBLIC KEY: " ownerpublickey
echo $ownerpublickey > ownerpublickey.txt
echo " "
read -p "ENTER YOUR OWNER PRIVATE KEY: " ownerprivatekey
echo " "
read -p "ENTER YOUR OWNER ACCOUNT NAME: " owneraccountname
echo $owneraccountname > owneraccountname.txt
echo " "
remcli wallet import --private-key=$ownerprivatekey

#-----------------------------------------------------------------------------------------------------
# YOUR REMNODE WALLET PASSWORD
#-----------------------------------------------------------------------------------------------------

echo " "
echo "TAKE NOTE OF YOUR WALLET PASSWORD:"
echo " "
cat ./walletpass
echo " "
pause 'Press [Enter] key to continue...'
echo " "

#-----------------------------------------------------------------------------------------------------
# IMPORTING EXISTING KEY PERMISSIONS
#-----------------------------------------------------------------------------------------------------

oldkeypermissions() {

read -p "ENTER YOUR REQUEST PUBLIC KEY: " requestpublickey
echo " "
read -p "ENTER YOUR REQUEST PRIVATE KEY: " requestprivatekey
echo " "
remcli wallet import --private-key=$requestprivatekey
echo " "
read -p "ENTER YOUR TRANSFER PRIVATE KEY: " transferprivatekey
echo " "
remcli wallet import --private-key=$transferprivatekey
echo " "
echo -e "plugin = eosio::chain_api_plugin\n\nplugin = eosio::net_api_plugin\n\nhttp-server-address = 0.0.0.0:8888\n\np2p-listen-endpoint = 0.0.0.0:9876\n\n# https://remme.io\n\np2p-peer-address = p2p.testchain.remme.io:2087\n\n# https://eon.llc\n\np2p-peer-address = 3.227.137.101:9877\n\n# https://remblock.pro\n\np2p-peer-address = 95.179.237.207:9877\n\np2p-peer-address = 45.77.59.14:9877\n\np2p-peer-address = 45.77.227.198:9877\n\np2p-peer-address = 45.77.56.243:9877\n\n# https://testnet.geordier.co.uk\n\np2p-peer-address = 45.76.132.248:9877\n\nverbose-http-errors = true\n\nchain-state-db-size-mb = 100480\n\nreversible-blocks-db-size-mb = 10480\n\nplugin = eosio::producer_plugin\n\nplugin = eosio::producer_api_plugin\n\nproducer-name = $owneraccountname\n\nsignature-provider = $requestpublickey=KEY:$requestprivatekey" > ./config/config.ini
echo " "
remcli system regproducer $owneraccountname $requestpublickey $domain
remcli system voteproducer prods $owneraccountname $owneraccountname -p $owneraccountname@vote
echo " "
remcli wallet remove_key $ownerpublickey --password=$producerwalletpass
echo " "
rm walletpass Install-1.sh Install-2.sh Install-3.sh domain.txt ownerpublickey.txt owneraccountname.txt producerwalletpass.txt
printf "\n[********************** COMPLETED ************************]\n\n"
}

#-----------------------------------------------------------------------------------------------------
# GENERATING RANDOM ACTIVE ACCOUNT NAMES
#-----------------------------------------------------------------------------------------------------

newkeypermissions() {

randomname1=$(cat /dev/urandom | tr -dc 'a-z1-5' | fold -w 12 | head -n 1 |  grep -o . | sort |tr -d "\n")
randomname2=$(cat /dev/urandom | tr -dc 'a-z1-5' | fold -w 12 | head -n 1 |  grep -o . | sort |tr -d "\n")
randomname3=$(cat /dev/urandom | tr -dc 'a-z1-5' | fold -w 12 | head -n 1 |  grep -o . | sort |tr -d "\n")
echo $randomname1 >> activeproducername.txt
echo $randomname2 >> activeproducername.txt
echo $randomname3 >> activeproducername.txt
sort activeproducername.txt
activeproducername1=$(head -n 1 activeproducername.txt | tail -1)
activeproducername2=$(head -n 2 activeproducername.txt | tail -1)
activeproducername3=$(head -n 3 activeproducername.txt | tail -1)

#-----------------------------------------------------------------------------------------------------
# CREATING YOUR REMNODE ACTIVE KEY 1
#-----------------------------------------------------------------------------------------------------

remcli create key --file key1
cp key1 activekeys1
sudo -S sed -i "/^Private key: /s/Private key: //" key1 && sudo -S sed -i "/^Public key: /s/Public key: //" key1
activepublickey1=$(head -n 2 key1 | tail -1)
activeprivatekey1=$(head -n 1 key1 | tail -1)
remcli wallet import --private-key=$activeprivatekey1
echo " "
echo "TAKE NOTE OF YOUR ACTIVE KEY 1:"
echo " "
echo "Account Name:" $activeproducername1
cat ./activekeys1
echo " "
pause 'Press [Enter] key to continue...'
echo " "

#-----------------------------------------------------------------------------------------------------
# CREATING YOUR REMNODE ACTIVE KEY 2
#-----------------------------------------------------------------------------------------------------

remcli create key --file key2
cp key2 activekeys2
sudo -S sed -i "/^Private key: /s/Private key: //" key2 && sudo -S sed -i "/^Public key: /s/Public key: //" key2
activepublickey2=$(head -n 2 key2 | tail -1)
activeprivatekey2=$(head -n 1 key2 | tail -1)
remcli wallet import --private-key=$activeprivatekey2
echo " "
echo "TAKE NOTE OF YOUR ACTIVE KEY 2:"
echo " "
echo "Account Name:" $activeproducername2
cat ./activekeys2
echo " "
pause 'Press [Enter] key to continue...'
echo " "

#-----------------------------------------------------------------------------------------------------
# CREATING YOUR REMNODE ACTIVE KEY 3
#-----------------------------------------------------------------------------------------------------

remcli create key --file key3
cp key3 activekeys3
sudo -S sed -i "/^Private key: /s/Private key: //" key3 && sudo -S sed -i "/^Public key: /s/Public key: //" key3
activepublickey3=$(head -n 2 key3 | tail -1)
activeprivatekey3=$(head -n 1 key3 | tail -1)
remcli wallet import --private-key=$activeprivatekey3
echo " "
echo "TAKE NOTE OF YOUR ACTIVE KEY 3:"
echo " "
echo "Account Name:" $activeproducername3
cat ./activekeys3
echo " "
pause 'Press [Enter] key to continue...'
echo " "

#-----------------------------------------------------------------------------------------------------
# CREATING YOUR REMNODE REQUEST KEY
#-----------------------------------------------------------------------------------------------------

remcli create key --file key4
cp key4 requestkeys
sudo -S sed -i "/^Private key: /s/Private key: //" key4 && sudo -S sed -i "/^Public key: /s/Public key: //" key4
requestpublickey=$(head -n 2 key4 | tail -1)
requestprivatekey=$(head -n 1 key4 | tail -1)
remcli wallet import --private-key=$requestprivatekey
echo -e "plugin = eosio::chain_api_plugin\n\nplugin = eosio::net_api_plugin\n\nhttp-server-address = 0.0.0.0:8888\n\np2p-listen-endpoint = 0.0.0.0:9876\n\n# https://remme.io\n\np2p-peer-address = p2p.testchain.remme.io:2087\n\n# https://eon.llc\n\np2p-peer-address = 3.227.137.101:9877\n\n# https://remblock.pro\n\np2p-peer-address = 95.179.237.207:9877\n\np2p-peer-address = 45.77.59.14:9877\n\np2p-peer-address = 45.77.227.198:9877\n\np2p-peer-address = 45.77.56.243:9877\n\n# https://testnet.geordier.co.uk\n\np2p-peer-address = 45.76.132.248:9877\n\nverbose-http-errors = true\n\nchain-state-db-size-mb = 100480\n\nreversible-blocks-db-size-mb = 10480\n\nplugin = eosio::producer_plugin\n\nplugin = eosio::producer_api_plugin\n\nproducer-name = $owneraccountname\n\nsignature-provider = $requestpublickey=KEY:$requestprivatekey" > ./config/config.ini
echo " "
echo "TAKE NOTE OF YOUR REQUEST KEYS:"
echo " "
cat ./requestkeys
echo " "
pause 'Press [Enter] key to continue...'
echo " "

#-----------------------------------------------------------------------------------------------------
# CREATING YOUR REMNODE TRANSFER KEY
#-----------------------------------------------------------------------------------------------------

remcli create key --file key5
cp key5 transferkeys
sudo -S sed -i "/^Private key: /s/Private key: //" key5 && sudo -S sed -i "/^Public key: /s/Public key: //" key5
transferprivatekey=$(head -n 1 key5 | tail -1)
remcli wallet import --private-key=$transferprivatekey
echo " "
echo "TAKE NOTE OF YOUR TRANSFER KEYS:"
echo " "
cat ./transferkeys
echo " "
pause 'Press [Enter] key to continue...'
echo " "

#-----------------------------------------------------------------------------------------------------
# CREATING YOUR REMCHAIN ACCOUNTS
#-----------------------------------------------------------------------------------------------------

echo "CREATING ACTIVE ACCOUNT NAME 1:"
echo " "
remcli system newaccount $owneraccountname $activeproducername1 $activepublickey1 $activepublickey1 -x 120 --transfer --stake "100.0000 REM" -p $owneraccountname@owner
pause 'Press [Enter] key to continue...'
echo " "
echo "CREATING ACTIVE ACCOUNT NAME 2:"
echo " "
remcli system newaccount $owneraccountname $activeproducername2 $activepublickey2 $activepublickey2 -x 120 --transfer --stake "100.0000 REM" -p $owneraccountname@owner
pause 'Press [Enter] key to continue...'
echo " "
echo "CREATING ACTIVE ACCOUNT NAME 3:"
echo " "
remcli system newaccount $owneraccountname $activeproducername3 $activepublickey3 $activepublickey3 -x 120 --transfer --stake "100.0000 REM" -p $owneraccountname@owner
echo " "
echo "Please wait for 2 minutes... "
echo " "
sleep 120

#-----------------------------------------------------------------------------------------------------
# CREATING YOUR MULTISIG PERMISSIONS
#-----------------------------------------------------------------------------------------------------

remcli set account permission $owneraccountname active '{"threshold":2,"keys":[],"accounts":[{"permission":{"actor":"'$activeproducername1'","permission":"active"},"weight":1},{"permission":{"actor":"'$activeproducername2'","permission":"active"},"weight":1},{"permission":{"actor":"'$activeproducername3'","permission":"active"},"weight":1}],"waits":[]}' owner -p $owneraccountname@owner
echo " "
printf "\n[********************** COMPLETED ************************]\n\n"
}

#-----------------------------------------------------------------------------------------------------
# CHECKING FOR EXISTING KEY PERMISSIONS
#-----------------------------------------------------------------------------------------------------

read -p "DO YOU HAVE EXISTING KEY PERMISSIONS? [y/n]: " yn2
  case $yn2 in
       y|Y ) oldkeypermissions
	     break;;
       n|N ) newkeypermissions
       	     break;;
       * )   echo "PLEASE ANSWER USING [y/n] or [Y/N]";;
   esac
