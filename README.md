# km-dyndns

A small cgi script providing a dnynamic dns service written in perl, using a mysql database.  
The script is desined to work for dyndns client integrated in the "FritzBox" routers, but can be customized for your needs.

## licence

GPLv2, see [LICENCE](LICENCE)

## dependencies

* bind9 dns server
* apache web server
* perl and some modules
	* cgi
	* dbi and dbd::mysql
	* mime::base64
* mysql database

## installation

the examples are meant for debian systems.

### create a new dns zone in bind

create zone file and key:

	sudo /usr/sbin/ddns-confgen -z dyn.example.com
	
this generates output like

	# To activate this key, place the following in named.conf, and
	# in a separate keyfile on the system or systems from which nsupdate
	# will be run:
	key "ddns-key.dyn.example.com" {
		algorithm hmac-sha256;
		secret "u/1n3/bDu2pBr9KaBhYaYxltA7QfjHIrx3e9HjxA/mk=";
	};
	
	# Then, in the "zone" definition statement for "dyn.example.com",
	# place an "update-policy" statement like this one, adjusted as 
	# needed for your preferred permissions:
	update-policy {
		  grant ddns-key.dyn.example.com zonesub ANY;
	};
	
	# After the keyfile has been placed, the following command will
	# execute nsupdate using this key:
	nsupdate -k <keyfile>

put the single parts of the output in your /etc/bind/named.conf.local file:

	key "ddns-key.dyn.example.com" {
	        algorithm hmac-sha256;
	        secret "u/1n3/bDu2pBr9KaBhYaYxltA7QfjHIrx3e9HjxA/mk=";
	};
	
	zone "dyn.example.com" {
	        type master;
	        file "/var/cache/bind/db.dyn.example.com";
	        update-policy {
	                grant ddns-key.dyn.example.com subdomain dyn.example.com. A;
	        };
	};
	
restart your bind9 daemon:

	sudo /etc/init.d/bind9 restart
	
(optional) try if your bind9 works as expected

	user@host:~> echo -e "update delete foo.dyn.example.com A\
	update add foo.dyn.example.com 60 127.0.0.1\
	show\
	send" | /usr/bin/nsupdate -y hmac-sha256:ddns-key.dyn.example.com:u/1n3/bDu2pBr9KaBhYaYxltA7QfjHIrx3e9HjxA/mk=
	
	Outgoing update query:
	;; ->>HEADER<<- opcode: UPDATE, status: NOERROR, id:      0
	;; flags:; ZONE: 0, PREREQ: 0, UPDATE: 0, ADDITIONAL: 0
	;; UPDATE SECTION:
	foo.dyn.example.com. 0	ANY	A	
	foo.dyn.example.com. 60	IN	A	127.0.0.1
	
	user@host:~> dig +short foo.dyn.example.com @127.0.0.1
	
	127.0.0.1
	
	user@host:~> echo -e "update delete foo.dyn.example.com A\
	send" | /usr/bin/nsupdate -y hmac-sha256:ddns-key.dyn.example.com:u/1n3/bDu2pBr9KaBhYaYxltA7QfjHIrx3e9HjxA/mk=


### set your server as primary nameserver for the zone

how you can do this depends on your provider.  
i created a new ns entry pointing to my server for a subdomain in the admin-panel of my provider.

### create database and insert custom records

create empty database

	mysql> create database dyndns;
	
load structure

	user@host:~> mysql -u root -p -B dyndns < mysql_setup.sql
	
insert custom records

	mysql> insert into user (username, password_hash, password_salt, email) values
		('foo', MD5(CONCAT('mypassword','mysupersecrethash')),'mysupersecrethash', 'foo@example.com');
	mysql> insert into zones (zone, `key`) values ('dyn.example.com', 'secretzoneupdatekey');
	mysql> insert into domains (zone_id, user_id, domain, ip) values (1, 1, 'foo', NULL);
	
### setup update.pl cgi script

#### set up apache to execute the cgi script and pass http auth to env variable

put the customized version of this example in your apache config:

	<Directory /mydir/>
		AddHandler cgi-script .pl
		RewriteEngine on
		RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization},L]
	</Directory>
	<Directory /var/www/example.com/httpdocs/mydir/>
		Options ExecCGI
	</Directory>
	
put update.pl in the directory and try to open http://example.com/mydir/update.pl in your browser.  
you should see the message "nohost", what means the script was beend executed by the webserver.

#### set database config in script
	
edit update.pl and change the following code:

	my $database = {
	  "host"     => "localhost",
	  "database" => "dyndns",
	  "user"     => "root",
	  "password" => "toor"
	};

### set the new update-script in your routers dyndns client

todo