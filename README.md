# seedy

This script will install a seedbox including rTorrent and ruTorrent on an Alpine Linux server. Only install this on a fresh Alpine Linux installation.

You can configure the hostname and user:
````
export SEEDY_HOST=sammy.example.com
export RTORRENT_USER=marco
````

And then run the script with wget:
````
wget -O - https://raw.githubusercontent.com/thde/seedy/master/seedy.sh | ash
````
or curl:
````
curl -s https://raw.githubusercontent.com/thde/seedy/master/seedy.sh | ash
````
