# dip
![SecuredNetwork_v3](https://user-images.githubusercontent.com/51214083/159584320-f4021206-b435-4cba-96d6-0e57e000911a.jpg)
Конфигурация защищенной сетевой инфраструктуры со всеми конфигами для московской "ветки".
Используемые средства:
1. nginx - reverse_proxy + web_server;
2. stunnel - прячет vpn_traffic за чистым HTTPS-трафиком(работает на внешнем IP на 45678 порту);
3. openvpn - шифрует трафик между reverse_proxy и web_server(работает на loopback интерфейсте на 1194 порту);
4. openssl + easyrsa - создание CA, сертификатов и их подпись.
