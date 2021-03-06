#!/bin/ash

# seedy.sh - v0.1

# This script will install a seedbox including rTorrent and ruTorrent on an Alpine Linux server. Only install this on a fresh Alpine Linux installation.
#
# You can configure the hostname and user BEFORE running ./seedy.sh:
# export SEEDY_HOST=sammy.example.com
# export RTORRENT_USER=marco

# set configuration
SEEDY_TMPDIR=$(mktemp -d)
SEEDY_CURDIR="$PWD"
SEEDY_HOST=${SEEDY_HOST:-$(hostname)}
SEEDY_TEST=${SEEDY_TEST:-false}
WWW_USER=${WWW_USER:-nginx}
WWW_PASSWORD=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c15)
RTORRENT_USER=${RTORRENT_USER:-rt}

mkdir "$SEEDY_TMPDIR/logs"

if [ "$SEEDY_TEST" = true ] ; then
    echo "Test mode active"
    set -x
    set -e
fi

echo ""
echo " Installing new Seedbox... "
echo ""

# prints configuration and login information
_SEEDY_PRINT_INFO () {
  echo " Temporary folder: $SEEDY_TMPDIR"
  echo " Hostname: $SEEDY_HOST"
  echo " User: $RTORRENT_USER"
  echo " Web auth: $WWW_PASSWORD"
}

_SEEDY_UPDATE_SYSTEM () {
  apk upgrade --update
}

_SEEDY_INSTALL_MEDIAINFO_SOURCE () {
  mkdir "$SEEDY_TMPDIR/mediainfo"
  cd "$SEEDY_TMPDIR/mediainfo" || return
  apk add build-base file libtool

  curl http://mediaarea.net/download/binary/mediainfo/0.7.82/MediaInfo_CLI_0.7.82_GNU_FromSource.tar.xz --output mediainfo.tar.xz
  tar xJf mediainfo.tar.xz
  cd MediaInfo_CLI_GNU_FromSource && ./CLI_Compile.sh
  cd MediaInfo/Project/GNU/CLI && make install

  apk del build-base file libtool
  cd "$SEEDY_CURDIR" || return
}

_SEEDY_INSTALL_SOFTWARE () {
  apk add \
  openrc \
  iptables \
  ip6tables \
  git \
  screen \
  ffmpeg \
  nginx \
  apache2-utils \
  curl \
  openssl \
  rtorrent \
  php-fpm \
  php-cli \
  php-json

  _SEEDY_INSTALL_MEDIAINFO_SOURCE
}

_SEEDY_ADD_USER () {
  adduser -D "$RTORRENT_USER"

  mkdir -p "/home/$RTORRENT_USER/watch"
  mkdir -p "/home/$RTORRENT_USER/files/incomplete"
  mkdir "/home/$RTORRENT_USER/.ssh"

  chmod -R 600 "/home/$RTORRENT_USER/.ssh"
  chmod 700 "/home/$RTORRENT_USER/.ssh"
  chown -R "$RTORRENT_USER":"$RTORRENT_USER" "/home/$RTORRENT_USER"
}

_SEEDY_INSTALL_RTORRENT () {
 curl -s https://raw.githubusercontent.com/thde/seedy/master/files/rtorrent.rc.tmpl > "/home/$RTORRENT_USER/.rtorrent.rc"
 SYSTEMRAM=$( (grep MemTotal | awk '{ print $2 }') < /proc/meminfo )
 ROTRRENTRAM=$(expr $SYSTEMRAM \* 90 / 100 / 1024)
 sed -i s/TMPLRAM/"${ROTRRENTRAM}M"/g "/home/$RTORRENT_USER/.rtorrent.rc"

 mkdir -p "/home/$RTORRENT_USER/.rtorrent/session"
 chown -R "$RTORRENT_USER":"$RTORRENT_USER" "/home/$RTORRENT_USER/.rtorrent"
 chown "$RTORRENT_USER":"$RTORRENT_USER" "/home/$RTORRENT_USER/.rtorrent.rc"
 chown -R "$RTORRENT_USER":nginx "/home/$RTORRENT_USER/.rtorrent/session"
 chmod g+s "/home/$RTORRENT_USER/.rtorrent/session"

 curl -s https://raw.githubusercontent.com/thde/seedy/master/files/rtorrentd.init.tmpl > /etc/init.d/rtorrentd
 sed -i s/TMPLUSER/"$RTORRENT_USER"/g /etc/init.d/rtorrentd
 chmod +x /etc/init.d/rtorrentd
 rc-update add rtorrentd
}

_SEEDY_INSTALL_NGINX () {
  cd "$SEEDY_CURDIR" || return

  mkdir -p /etc/ssl/private/self/
  openssl req -new -x509 -nodes -days 3650 -subj "/CN=$SEEDY_HOST" -keyout "/etc/ssl/private/self/$SEEDY_HOST.key" -out "/etc/ssl/private/self/$SEEDY_HOST.crt"
  chmod 600 -R /etc/ssl/private/self/

  htpasswd -bcB /etc/nginx/htpasswd "$RTORRENT_USER" "$WWW_PASSWORD"

  mkdir -p /var/cache/nginx
  chown "$WWW_USER":"$WWW_USER" /var/cache/nginx

  cp -f /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig
  curl -s https://raw.githubusercontent.com/thde/seedy/master/files/nginx.conf.tmpl > /etc/nginx/nginx.conf

  curl -s https://raw.githubusercontent.com/thde/seedy/master/files/virtualhost.conf.tmpl > "/etc/nginx/conf.d/$SEEDY_HOST.conf"
  sed -i s/TMPLHOSTNAME/"$SEEDY_HOST"/g "/etc/nginx/conf.d/$SEEDY_HOST.conf"

  rc-update add nginx
}

_SEEDY_INSTALL_PHP () {
  sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g' /etc/php/php.ini

  sed -i 's/user = nobody/user = nginx/g' /etc/php/php-fpm.conf
  sed -i 's/group = nobody/group = nginx/g' /etc/php/php-fpm.conf
  sed -i 's/listen = 127.0.0.1:9000/;listen = 127.0.0.1:9000\nlisten = \/var\/run\/php5-fpm.sock/g' /etc/php/php-fpm.conf
  sed -i 's/;listen.owner = nobody/listen.owner = nginx/g' /etc/php/php-fpm.conf
  sed -i 's/;listen.group = nobody/listen.group = nginx/g' /etc/php/php-fpm.conf
  sed -i 's/;listen.mode = 0660/listen.mode = 0660/g' /etc/php/php-fpm.conf

  rc-update add php-fpm
}

_SEEDY_INSTALL_RUTORRENT () {
  SEEDY_TMPDIR_RUTORRENT="$SEEDY_TMPDIR/rutorrent"
  mkdir "$SEEDY_TMPDIR_RUTORRENT"

  rm -rf /var/www/html/*
  git clone https://github.com/Novik/ruTorrent /var/www/html

  sed -i "s/\$topDirectory = '\/';/\$topDirectory = '\/home\/$RTORRENT_USER\/';/g" /var/www/html/conf/config.php
  rm -rf /var/www/html/plugins/rss
  rm -rf /var/www/html/plugins/rssurlrewrite
  rm -rf /var/www/html/plugins/unpack

  chown -R nginx:nginx /var/www/html/share/
}

_SEEDY_CONFIG_FIREWALL () {
  iptables -P INPUT ACCEPT # allow anything
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT

  ip6tables -P INPUT ACCEPT # allow anything
  ip6tables -P FORWARD ACCEPT
  ip6tables -P OUTPUT ACCEPT

  iptables -F #remove existing rules
  ip6tables -F

  iptables -A INPUT -i lo -j ACCEPT # allow loopback
  iptables -A OUTPUT -o lo -j ACCEPT

  ip6tables -A INPUT -i lo -j ACCEPT
  ip6tables -A OUTPUT -o lo -j ACCEPT

  iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT # allow existent connections
  ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  ip6tables -A INPUT -p icmpv6 -j ACCEPT # allow icmpv6
  ip6tables -A OUTPUT -p icmpv6 -j ACCEPT

  iptables -A INPUT -p tcp --dport 22 -j ACCEPT # allow ssh
  iptables -A INPUT -p tcp --dport 443 -j ACCEPT # allow https
  iptables -I INPUT -p udp --dport 6881 -j ACCEPT
  iptables -I INPUT -p tcp --dport 61000:61100 -j ACCEPT # torrent
  iptables -I INPUT -p udp --dport 61000:61100 -j ACCEPT # torrent


  ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT
  ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT
  ip6tables -I INPUT -p udp --dport 6881 -j ACCEPT
  ip6tables -I INPUT -p tcp --dport 61000:61100 -j ACCEPT
  ip6tables -I INPUT -p udp --dport 61000:61100 -j ACCEPT


  iptables -P INPUT DROP # drop incoming
  iptables -P FORWARD DROP # drop forwarded
  iptables -P OUTPUT ACCEPT

  ip6tables -P INPUT DROP
  ip6tables -P FORWARD DROP
  ip6tables -P OUTPUT ACCEPT

  rc-update add iptables
  rc-update add ip6tables

  /etc/init.d/iptables save
  /etc/init.d/ip6tables save
}

_SEEDY_START () {
  service nginx start
  service php-fpm start
  service rtorrentd start
}

if [ "$SEEDY_TEST" = true ] ; then
  _SEEDY_UPDATE_SYSTEM
  _SEEDY_INSTALL_SOFTWARE
  _SEEDY_ADD_USER
  _SEEDY_INSTALL_RTORRENT
  _SEEDY_INSTALL_NGINX
  _SEEDY_INSTALL_PHP
  _SEEDY_INSTALL_RUTORRENT

  nginx -t
  php-fpm -t

  exit 0
fi

_SEEDY_UPDATE_SYSTEM &> "$SEEDY_TMPDIR/logs/update.log"
_SEEDY_INSTALL_SOFTWARE &> "$SEEDY_TMPDIR/logs/install.log"
_SEEDY_ADD_USER &> "$SEEDY_TMPDIR/logs/user.log"
_SEEDY_INSTALL_RTORRENT &> "$SEEDY_TMPDIR/logs/rtorrent.log"
_SEEDY_INSTALL_NGINX &> "$SEEDY_TMPDIR/logs/nginx.log"
_SEEDY_INSTALL_PHP &> "$SEEDY_TMPDIR/logs/php.log"
_SEEDY_INSTALL_RUTORRENT &> "$SEEDY_TMPDIR/logs/rutorrent.log"
_SEEDY_CONFIG_FIREWALL &> "$SEEDY_TMPDIR/logs/firewall.log"
_SEEDY_START &> "$SEEDY_TMPDIR/logs/start.log"
_SEEDY_PRINT_INFO | tee  "$SEEDY_TMPDIR/logs/info.log"

exit 0
