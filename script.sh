#!/bin/bash

echo "Creating user openvpn if not exists"
#Создадим нового пользователя openvpn с правами администратора
#Проверка на наличие пользователя в системе, для отсутствия ошибок при повторном запуске
username=openvpn
client_name=client

grep "^$username:" /etc/passwd >/dev/null
if [[ $? -ne 0 ]]; then
  adduser openvpn
  usermod -aG wheel openvpn
  passwd openvpn
  echo "User openvpn created."
else
  echo "User openvpn already exists!"
fi
###Создание клиентов по умолчанию
echo "Enter default count of clients:"
read -r client_count
#Проверка-значение число, иначе сначала
if [[ $client_count =~ ^[0-9]+$ ]]; then
   echo "Будет создано ""$client_count"" клиентских конфигураций с именами ""$client_name""[X].ovpn"
else
   client_count=10
   echo "Будет создано ""$client_count"" клиентских конфигураций с именами ""$client_name""[X].ovpn"
fi

#Проверка наличия директории openvpn если есть то удаляем и Создание заново, иначе Создание
if [[ -e /etc/openvpn ]]; then
   rm -rf /etc/openvpn
   mkdir /etc/openvpn
   mkdir /etc/openvpn/keys
   chown -R openvpn:openvpn /etc/openvpn
   echo "Удалена старая директория openvpn, создана новая"
else
   mkdir /etc/openvpn
   mkdir /etc/openvpn/keys
   chown -R openvpn:openvpn /etc/openvpn
   echo "Cоздана новая директория openvpn"
fi
#Copying easy-rsa to openvpn directory
sudo cp -R /usr/share/easy-rsa /etc/openvpn

#Create file named vars with user's configurations
touch /etc/openvpn/easy-rsa/vars

# Default vars
echo "Enter main configurations for certs creation"
echo "All values are not important besides certs validity"

echo "Country(def - RU):"
read -r country
if [[ -z $country ]]; then
   country="RU"
fi
echo "Key size(def - 1024):"
read -r key_size
if [[ $key_size =~ ^[0-9]+$ ]]; then #check: is key a number?
   echo "Key size:" "$key_size"
else
   key_size=2048
   echo "Key size was set 2048"
fi
echo "Enter region(def - Moscow)"
read -r region
if [[ -z $region ]]; then
   region="Moscow"
fi
echo "City(def - Moscow)"
read -r city
if [[ -z $city ]]; then
   city="Moscow"
fi
echo "email(def - example@example.com)"
read -r mail
if [[ -z $mail ]]; then
   mail="example@example.com"
fi
echo "Certificate validity, days(def - 3650/10 years): "
read -r expire
if [[ $expire =~ ^[0-9]+$ ]]; then
   echo "Cert validity" "$expire" "days"
else
   expire=3650
   echo "Cert validity" "$expire" "days"
fi

#Entering vars
cat <<EOF >/etc/openvpn/easy-rsa/vars
#### FOR Domain
####set_var EASYRSA_DN $domain_name

set_var EASYRSA_REQ_COUNTRY $country
set_var EASYRSA_KEY_SIZE $key_size
set_var EASYRSA_REQ_region $region
set_var EASYRSA_REQ_CITY $city
set_var EASYRSA_REQ_ORG $domain_name
set_var EASYRSA_REQ_EMAIL $mail
set_var EASYRSA_REQ_OU $domain_name
set_var EASYRSA_REQ_CN changeme
set_var EASYRSA_CERT_EXPIRE $expire
set_var EASYRSA_DH_KEY_SIZE $key_size
EOF

#Init PKI
cd /etc/openvpn/easy-rsa/ || exit; /etc/openvpn/easy-rsa/easyrsa init-pki
sudo dd if=/dev/urandom of=pki/.rand bs=256 count=1 
sudo dd if=/dev/urandom of=pki/.rnd bs=256 count=1 
#Создание ключа центра сертификации
/etc/openvpn/easy-rsa/easyrsa build-ca nopass

#Создание сертификата сервера
/etc/openvpn/easy-rsa/easyrsa build-server-full server_cert nopass

#Создание файл Диффи Хелмана
/etc/openvpn/easy-rsa/easyrsa gen-dh

#Crl для информации об активных/отозванных сертификатов
/etc/openvpn/easy-rsa/easyrsa gen-crl

#Добавление HMAC
sudo openvpn --genkey --secret /etc/openvpn/keys/ta.key

#Теперь копируем все что создали в папку keys
cp /etc/openvpn/easy-rsa/pki/ca.crt /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/easy-rsa/pki/dh.pem /etc/openvpn/keys/
cp /etc/openvpn/easy-rsa/pki/issued/server_cert.crt /etc/openvpn/keys/
cp /etc/openvpn/easy-rsa/pki/private/server_cert.key /etc/openvpn/keys/

#Получение данных для файла server.conf
echo "Сейчас соберем информацию для файла конфигурации сервера."
echo "Порт(по умолчанию 1194):"
read -r port_num
if [[ $port_num =~ ^[0-9]+$ ]]; then #проверка на число
   echo "Установлен порт:" "$port_num"
else
   port_num=1194
   echo "Номер порта установлен по умолчанию"
   echo "Протокол(по умолчанию udp)для установки tcp введите 1"
   read -r protocol
fi
if [[ $protocol -eq 1 ]]; then
   protocol="tcp"
   echo "Выбран протокол tcp"
else
   protocol="udp"
   echo "Выбран протокол udp"
fi

#Создание директории для логов
mkdir /var/log/openvpn
touch /var/log/openvpn/{openvpn-status,openvpn}.log
chown -R openvpn:openvpn /var/log/openvpn


#Создание server.conf
mkdir /etc/openvpn/server
touch /etc/openvpn/server/server.conf
chmod -R a+r /etc/openvpn
cat <<EOF >/etc/openvpn/server/server.conf
port $port_num
proto $protocol
dev tun
ca /etc/openvpn/keys/ca.crt
cert /etc/openvpn/keys/server_cert.crt
key /etc/openvpn/keys/server_cert.key
dh /etc/openvpn/keys/dh.pem
crl-verify /etc/openvpn/keys/crl.pem
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist /var/log/openvpn/ipp.txt
#route 172.31.1.0 255.255.255.0
#push "dhcp-option DNS 8.8.8.8"
#push "dhcp-option DNS 8.8.4.4"
push "redirect-gateway def1 bypass-dhcp"
tls-auth /etc/openvpn/keys/ta.key 0
keepalive 10 120
cipher AES-256-CBC
persist-key
persist-tun
status /var/log/openvpn/openvpn-status.log
log-append /var/log/openvpn/openvpn.log
verb 4
explicit-exit-notify 1
#mute 20
#daemon
#mode server
#user nobody
#group nobody
EOF
echo "Добавим сервер в автозагрузку и запустим"
chown -R openvpn:openvpn /var/log/openvpn
chmod -R a+rw /var/log/openvpn
#sudo systemctl enable openvpn-server@server
sudo systemctl start openvpn-server@server
sudo systemctl status openvpn-server@server
##chmod -R a+r /etc/openvpn

###Настройка маршрутизации трафика
#Выбор внешнего интерфейса
interface=""
echo "Enter interface name:"
read -r interface
if [ -z "$interface" ]; then
    interface="$(ip route | grep default | head -n 1 | awk '{print $5}')"
fi
echo "Selected interface: $interface"

#Включение форвардинга трафика
echo net.ipv4.ip_forward=1 >>/etc/sysctl.conf
sysctl -p /etc/sysctl.conf
#iptables
iptables -I FORWARD -j ACCEPT
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $interface -j MASQUERADE

#Создание клиентов
#Директория для готовых конфигов
mkdir /home/openvpn/ready_conf
echo "IP к которому необходимо подключаться клиентам в формате 111.111.111.111"
read ip_adress
#Создадим темповый файл конфигурации клиента
touch /home/openvpn/temp_conf_client.txt
cat <<EOF >/home/openvpn/temp_conf_client.txt
client
remote $ip_adress
port $port_num
dev tun
proto $protocol
key-direction 1
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3
EOF
#теперь функция создания клиентов
create_client() {
   cd /etc/openvpn/easy-rsa/
   /etc/openvpn/easy-rsa/easyrsa build-client-full "$client_name$client_count" nopass
   cp /home/openvpn/temp_conf_client.txt /home/openvpn/ready_conf/"$client_name$client_count"'.ovpn'
   {
      echo "<ca>"
      cat "/etc/openvpn/keys/ca.crt"
      echo "</ca>"
      echo "<cert>"
      awk '/BEGIN/,/END/' "/etc/openvpn/easy-rsa/pki/issued/$client_name$client_count.crt"
      echo "</cert>"
      echo "<key>"
      cat "/etc/openvpn/easy-rsa/pki/private/$client_name$client_count.key"
      echo "</key>"
      echo "<dh>"
      cat "/etc/openvpn/keys/dh.pem"
      echo "</dh>"
      echo "<tls-auth>"
      cat "/etc/openvpn/keys/ta.key"
      echo "</tls-auth>"
   } >>"/home/openvpn/ready_conf/"$client_name$client_count".ovpn"

} #Запускать функцию создания клиентов, по счетчику
while [[ $client_count -ne 0 ]]; do
   create_client
   let "client_count=$client_count-1"
done
/etc/openvpn/easy-rsa/easyrsa gen-crl     #генерируем crl для информации об активных сертификатах
cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/keys/ #Копируем в директорию с активными сертификатами
sudo systemctl restart openvpn-server@server   #перезапускаем сервер, для применения crl
cd /home/openvpn/ready_conf/
ls -alh ./
echo "сейчас вы в директории с готовыми файлами конфигураций, их уже можно использовать"
echo "скрипт завершен успешно"
exec bash
