#!/bin/bash

#openshift nginx-google-proxy

NGINX_VERSION='1.11.4'
PCRE_VERSION='8.38'

cd $OPENSHIFT_TMP_DIR

wget http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
tar xzf nginx-${NGINX_VERSION}.tar.gz

git clone https://github.com/FRiCKLE/ngx_cache_purge.git
git clone https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git
git clone https://github.com/cuber/ngx_http_google_filter_module.git

cd ${OPENSHIFT_TMP_DIR}nginx-${NGINX_VERSION}

./configure --prefix=$OPENSHIFT_DATA_DIR \
--with-pcre=${OPENSHIFT_TMP_DIR}pcre-${PCRE_VERSION} \
--with-openssl=${OPENSHIFT_TMP_DIR}openssl \
--with-http_v2_module \
--with-http_ssl_module \
--with-ipv6 \
--with-http_gzip_static_module \
--add-module=../ngx_http_google_filter_module \
--add-module=${OPENSHIFT_TMP_DIR}ngx_http_substitutions_filter_module \
--add-module=${OPENSHIFT_TMP_DIR}ngx_cache_purge

make -j4 && make install
cd /tmp
rm -rf *
cd ${OPENSHIFT_REPO_DIR}.openshift/action_hooks
rm -rf start
cat>start<<EOF
#!/bin/bash
# The logic to start up your application should be put in this
# script. The application will work only if it binds to
# \$OPENSHIFT_DIY_IP:8080
#nohup \$OPENSHIFT_REPO_DIR/diy/testrubyserver.rb \$OPENSHIFT_DIY_IP \$OPENSHIFT_REPO_DIR/diy |& /usr/bin/logshifter -tag diy &
nohup \$OPENSHIFT_DATA_DIR/sbin/nginx > \$OPENSHIFT_LOG_DIR/server.log 2>&1 &
EOF
chmod 755 start
cd ${OPENSHIFT_REPO_DIR}.openshift/cron/minutely
rm -rf restart.sh
cat>restart.sh<<EOF
#!/bin/bash
export TZ='Asia/Shanghai'
curl -I \${OPENSHIFT_APP_DNS} 2> /dev/null | head -1 | grep -q '200\|301\|302\|404\|403'
s=\$?
if [ \$s != 0 ];
	then
		echo "`date +"%Y-%m-%d %H:%M:%S"` down" >> \${OPENSHIFT_LOG_DIR}web_error.log
		echo "`date +"%Y-%m-%d %H:%M:%S"` restarting..." >> \${OPENSHIFT_LOG_DIR}web_error.log
		killall nginx
		nohup \${OPENSHIFT_DATA_DIR}/sbin/nginx > \${OPENSHIFT_LOG_DIR}/server.log 2>&1 &
		#/usr/bin/gear start 2>&1 /dev/null
		echo "`date +"%Y-%m-%d %H:%M:%S"` restarted!!!" >> \${OPENSHIFT_LOG_DIR}web_error.log		
else
	echo "`date +"%Y-%m-%d %H:%M:%S"` is ok" > \${OPENSHIFT_LOG_DIR}web_run.log
fi
EOF
chmod 755 restart.sh
touch nohup.out
chmod 755 nohup.out
rm -rf delete_log.sh
cat>delete_log.sh<<EOF
#!/bin/bash
export TZ="Asia/Shanghai"
# 每天 00:30 06:30 12:30 18:30 删除一次网站日志
hour="`date +%H%M`"
if [ "\$hour" = "0030" -o "\$hour" = "0630" -o "\$hour" = "1230" -o "\$hour" = "1830" ]
then
  echo "Scheduled delete at \$(date) ..." >&2
  (
  sleep 1
  cd \${OPENSHIFT_LOG_DIR}
  rm -rf *
  echo "delete OPENSHIFT_LOG at \$(date) ..." >&2
  sleep 1
  cd \${OPENSHIFT_DATA_DIR}/logs
  rm -rf *.log
  echo "delete nginx logs at \$(date) ..." >&2
  ) &
  exit
fi
EOF
chmod 755 delete_log.sh

cd $OPENSHIFT_DATA_DIR/conf
rm nginx.conf
cat>nginx.conf<<EOF

worker_processes  1;
worker_cpu_affinity 0001;

events {
    use epoll;
    worker_connections  1024;
}


http {
    include       mime.types;
    default_type  application/octet-stream;
    port_in_redirect off;
    server_tokens off;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';


    client_header_buffer_size 32k; 
    sendfile        on;
    client_max_body_size 100m;
    client_body_buffer_size 512k;
    client_header_timeout 3m;  
    client_body_timeout 3m;  
    tcp_nopush     on;
    tcp_nodelay    on;
    #keepalive_timeout  0;
    keepalive_timeout  65;
    gzip_static on;
    gzip  on;
    gzip_disable "MSIE [1-6]\.";
    gzip_min_length  10k;
    gzip_buffers     4 16k;
    #gzip_http_version 1.0;
    gzip_comp_level 3;
    gzip_types text/plain application/x-javascript text/css application/xml;
    gzip_vary on;
	
    server {
        listen       OPENSHIFT_DIY_IP:OPENSHIFT_DIY_PORT;
        server_name  xxx-xxx.rhcloud.com;

        location / {
            google on;
			google_scholar on;
            google_language en;
            if ($http_user_agent ~* (baiduspider|googlebot|soso|bing|sogou|yahoo|sohu-search|yodao|YoudaoBot|robozilla|msnbot|MJ12bot|NHN|Twiceler)){ return 403; }
        }
    }
}

EOF
sed -i "s/OPENSHIFT_DIY_IP/$OPENSHIFT_DIY_IP/g" nginx.conf
sed -i "s/OPENSHIFT_DIY_PORT/$OPENSHIFT_DIY_PORT/g" nginx.conf
sed -i "s/xxx-xxx.rhcloud.com/$OPENSHIFT_APP_DNS/g" nginx.conf
gear stop
gear start
