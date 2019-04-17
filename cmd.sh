# 初始化目录结构和文件
# 文件和目录命名参照默认的openssl.cnf配置文件
# 当前目录:     CA根目录
# private:      存放CA证书的秘钥
# certs:        存放CA证书
# newcerts:     存放新生成的服务端或客户端证书, 一般以序列号命名
# serial:       序列号, 需给定初始值, 可随意设置为01、1000等
# index.txt:    文本数据库, 签发证书后会更新该数据库
mkdir certs crl csr newcerts private
echo 1000 > crlnumber && echo 1000 > serial && touch index.txt


#### 制作CA根证书 ####
# 生成CA根证书私钥: 为保证安全, 生成一个4096位的私钥, 并使用aes方式加密
openssl genrsa -aes256 -out private/rootca.key.pem 4096
# 生成自签名的CA根证书
openssl req -config openssl.cnf -new -x509 -days 3650 -sha256 -extensions v3_ca -key private/rootca.key.pem -out certs/rootca.cert.pem -subj "/C=CN/ST=Shanghai/L=Shanghai/O=Internet Widgits Pty Ltd/OU=Certificate Authority/CN=Pty Root CA"
# 查看证书内容, 以确保证书生成正确
openssl x509 -noout -text -in certs/rootca.cert.pem


#### 制作代理CA证书(中间商CA) ####
# 制作代理CA证书不是必须的, 这里之所以要多此一步, 是因为:
# 根证书的安全必须得到充分的保证, 听说要断开网络、拔掉网线和网卡, 还要离线存储, 放入保险箱
# 在现实商业逻辑中, 代理CA的存在也是相当普遍
# 学习嘛, 就是要想办法给自己增加难度
# FBI Warning
# 用代理CA签发客户端证书的话, 在服务端的配置需要特别注意, 以 nginx 为例:
# 必须设定: ssl_verify_depth 2; 即客户端证书链的验证深度, 默认值为1; 因为代理CA之上还有根CA, 所以这里要设置为2, 否则无法校验通过

# 生成代理CA证书私钥: 同样适用4096位, 不加密了
openssl genrsa -out private/intermediateca.key.pem 4096
# 生成签发请求
openssl req -new -key private/intermediateca.key.pem -out csr/intermediateca.csr.pem -subj "/C=CN/ST=Shanghai/L=Shanghai/O=Internet Widgits Pty Ltd/OU=Certificate Authority/CN=Pty Intermediateca CA"
# 用CA根证书签发该代理CA证书请求
openssl x509 -req -extfile openssl.cnf -extensions v3_ca -days 730 -sha256 -CA certs/rootca.cert.pem -CAkey private/rootca.key.pem -CAcreateserial -CAserial serial -in csr/intermediateca.csr.pem -out certs/intermediateca.cert.pem
# 查看代理CA证书内容, 以确保证书生成正确
openssl x509 -noout -text -in certs/intermediateca.cert.pem
# 用根证书校验代理CA证书, 确认是否通过
openssl verify -CAfile certs/rootca.cert.pem certs/intermediateca.cert.pem
# 合并证书链, 在校验代理CA签发的证书时需要使用证书链验证
cat certs/intermediateca.cert.pem certs/rootca.cert.pem > certs/intermediateca-chain.cert.pem


#### 接下来是重头戏, 使用代理CA制作服务端和客户端证书 ####
# 注: 一般域名服务商会提供免费的服务端证书, 如阿里云、腾讯云
# 创建基于域名的文件夹, 暂且放在newcerts目录下吧
domain=www.example.com
mkdir newcerts/${domain}

# 生成服务端证书私钥: 期限相对较短, 所以用2048位足以
openssl genrsa -out newcerts/${domain}/server.key.pem 2048
# 生成签发请求
openssl req -new -key newcerts/${domain}/server.key.pem -out newcerts/${domain}/server.csr.pem -subj "/C=CN/ST=Shanghai/L=Shanghai/O=Internet Widgits Pty Ltd/OU=Certificate Authority/CN=${domain}"
# 用代理CA证书签发证书
openssl x509 -req -extfile openssl.cnf -extensions usr_cert -days 365 -sha256 -CA certs/intermediateca.cert.pem -CAkey private/intermediateca.key.pem -CAserial serial -in newcerts/${domain}/server.csr.pem -out newcerts/${domain}/server.cert.pem
# 查看生成的证书内容
openssl x509 -noout -text -in newcerts/${domain}/server.cert.pem
# 使用 根证书+代理证书 证书链校验生成的服务端证书的正确性
openssl verify -CAfile certs/intermediateca-chain.cert.pem newcerts/${domain}/server.cert.pem
# 继续合并证书链, 当然你也可以选择不合并
# 在服务端配置server端的证书时使用改证书链, 可以避免浏览器提示 `Windows没有足够信息, 不能验证该证书`
# 但即便获取到完整的证书链, 依然会提示 `无法将这个证书验证到一个受信任的证书颁发机构`
cat newcerts/www.example.com/server.cert.pem certs/intermediateca.cert.pem certs/rootca.cert.pem > newcerts/www.example.com/server-chain.cert.pem

# 如下是生成客户端证书的步骤, 仔细看, 跟生成服务端证书没有啥子差别
# 证书都是正经一样的证书, 只是看你怎么用, 用在哪而已
# 当然你也可以差异化的定制一些东西
openssl genrsa -out newcerts/${domain}/client.key.pem 2048
openssl req -new -key newcerts/${domain}/client.key.pem -out newcerts/${domain}/client.csr.pem -subj "/C=CN/ST=Shanghai/L=Shanghai/O=Internet Widgits Pty Ltd/OU=Certificate Authority/CN=${domain}"
openssl x509 -req -extfile openssl.cnf -extensions usr_cert -days 365 -sha256 -CA certs/intermediateca.cert.pem -CAkey private/intermediateca.key.pem -CAserial serial -in newcerts/${domain}/client.csr.pem -out newcerts/${domain}/client.cert.pem
openssl x509 -noout -text -in newcerts/${domain}/client.cert.pem
openssl verify -CAfile certs/intermediateca-chain.cert.pem newcerts/${domain}/client.cert.pem

# 最后, 将客户端证书导出为 pkcs12 格式, 这样支持在PC上傻瓜式的一键安装
openssl pkcs12 -export -clcerts -in newcerts/${domain}/client.cert.pem -inkey newcerts/${domain}/client.key.pem -out newcerts/${domain}/client.p12
