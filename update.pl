#!/usr/bin/env perl

#
# This file is part of km-dyndns. km-dyndns is free software: you can
# redistribute it and/or modify it under the terms of the GNU General Public
# License as published by the Free Software Foundation, version 2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 51
# Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# Copyright (c) 2013 - 2015 Klaus Meyer
# http://www.klaus-meyer.net/
#

use strict;
use CGI;
use MIME::Base64;
use DBI;

# --------------------------------------------------------------------------------
# Database Configuration
# --------------------------------------------------------------------------------

my $database = {
  "host"     => $ENV{"MYSQL_HOST"} || "localhost",
  "database" => $ENV{"MYSQL_BASE"} || "dyndns",
  "user"     => $ENV{"MYSQL_USER"} || "root",
  "password" => $ENV{"MYSQL_PASS"} || "toor"
};

# --------------------------------------------------------------------------------
# Nameserver Configuration
# --------------------------------------------------------------------------------

my $nameserver = {
  "host" => $ENV{"DNS_HOST"} || "",
  "port" => $ENV{"DNS_PORT"} || "53"
};

# --------------------------------------------------------------------------------
# Functions
# --------------------------------------------------------------------------------

# Extract Username or Password form HTTP_AUTHORIZATION ENV-Variable.
# The ENV-Variable is set by Apache-Modrewrite directive
sub get_http_auth {
  my $what = shift;
  my $auth = decode_base64(substr($ENV{"HTTP_AUTHORIZATION"}, 6));
  my @array = split(/:/, $auth);
  return @array[0] if $what eq "user";
  return @array[1] if $what eq "password";
  return "";
}

# Send a message to the client and terminate execution of the script.
# This is used as an replacement for the die() function in cgi enviroment.
sub send_message {
  my $message = shift;
  print $message . "\n";
  exit;
}

# --------------------------------------------------------------------------------
# Main Script
# --------------------------------------------------------------------------------

my $cgi = new CGI;

# Check if Basic Auth is provided and raise error if not
unless($ENV{"HTTP_AUTHORIZATION"}) {
  print "WWW-Authenticate: Basic realm=\"DynDNS Update\"\n";
  print "Status: 401 Unauthorized\n\n";
  print "badauth";
  exit;
}

print "Content-type: text/text\n\n";

# Collect parameters from different locations
# The domain is read from an url/form parameter
# The username and Password are read from HTTP basic auth
# The ip is read from ENV-Variables set by CGI
my $params = {
  "domain"   => $cgi->param("domain") || "",
  "user"     => get_http_auth("user") || "",
  "password" => get_http_auth("password") || "",
  "ip"       => $ENV{"HTTP_X_REAL_IP"} || $ENV{"HTTP_X_FORWARDED_FOR"} || $ENV{"REMOTE_ADDR"} || ""
};

# Validate if all necessary parameters are provided and raise error if not
send_message "nohost"  if $params->{"domain"} eq "";
send_message "badauth" if $params->{"user"} eq "" || $params->{"password"} eq "";

# Connect to the MySQL-Database
my $dbh = DBI->connect("DBI:mysql:$database->{'database'};host=$database->{'host'}", $database->{"user"}, $database->{"password"}) or send_message("911");

# Check if provided parameters are valid and if the user has access to the
# desired domain.
my $profile = $dbh->selectrow_hashref(
"
  SELECT u.user_id, d.domain_id, z.zone, z.key
  FROM user AS u
  INNER JOIN domains AS d
    ON d.user_id = u.user_id
  INNER JOIN zones AS z
    ON z.zone_id = d.zone_id
  WHERE u.username = ?
    AND MD5(CONCAT(?, u.password_salt)) = u.password_hash
    AND CONCAT(d.domain, '.', z.zone) = ?
", undef, $params->{"user"}, $params->{"password"}, $params->{"domain"});

unless($profile) { send_message "badauth"; }

# Set the current IP for desired domain
my $sth = $dbh->prepare("UPDATE domains SET ip = ? WHERE domain_id = ?");
$sth->execute($params->{"ip"}, $profile->{"domain_id"});

# Update IP in DNS server using nsupdate and the secret key stored for the zone in database
open(NSUPDATE, "| /usr/bin/nsupdate -y hmac-sha256:ddns-key." . $profile->{"zone"} . ":" . $profile->{"key"});


print NSUPDATE "server $nameserver->{'host'} $nameserver->{'port'}\n" unless $nameserver->{"host"} eq "";
print NSUPDATE "update delete " . $params->{"domain"} . " A\n";
print NSUPDATE "update add " . $params->{"domain"} . " 60 A " . $params->{"ip"} . "\n";
print NSUPDATE "send\n";

close(NSUPDATE);

# Send message to client to inform it everything went fine
send_message "good " . $params->{"ip"} . " " . $params->{"domain"};

1;
