#!/usr/bin/env perl
# Open Weather 0.22
# Script: openweather_forecast.pl rev 15
# Developer: Jade E. Deane (jade.deane@gmail.com)
# Purpose: Fetch NOAA forecasts.
#
# License: Distributed under the GNU General Public License.

use strict;

use DBI;
use LWP::UserAgent;

my $dbh;

my %openweather;
my $Configfile = "";
open (CONF,$Configfile) or die "Could not open config file $Configfile: $! \n";
my $code = join ('', <CONF>);
close (CONF);
eval $code;

my $noaa_server = $openweather{'noaa_server'};
my $db_type = $openweather{'db_type'};
my $db_username = $openweather{'db_username'};
my $db_password = $openweather{'db_password'};
my $db_hostname = $openweather{'db_hostname'};
my $db_database = $openweather{'db_database'};

sub db_establish { 
    # Establish connection with database.
    my %DBConnectOpts = ( 
		PrintError => 0, 
		RaiseError => 0 
	);
    my $DSN = "DBI:$db_type:$db_database:$db_hostname";
    $dbh = DBI->connect($DSN, $db_username, $db_password, \%DBConnectOpts) or die();
}

sub main {
	db_establish();
	my $sql = "SELECT icao,place,state FROM si WHERE country='United States' ORDER BY state,place";
	my $sth = $dbh->prepare ($sql) or db_error();
	$sth->execute() || db_error();
	my $w = 0;
	while (my @row = $sth->fetchrow_array) {
		$w++;
		my @sitei = split(",", $row[1]);
		$sitei[0] =~ s/\///;
		$sitei[0] =~ s/,//;
		$sitei[0] =~ s/'//;
		$sitei[0] =~ s/\s/_/g;
		$sitei[0] =~ s/__/_/g;		
		my $city = lc($sitei[0]);
		my $state = lc($row[2]);
		my $url = "http://$noaa_server/pub/data/forecasts/city/$state/$city".".txt";
		#print "[$w] Attemping to fetch $city, $state from $url\n";
		my $ua = new LWP::UserAgent;
		my $request = new HTTP::Request('GET', $url);
		my $response = $ua->request($request);
		my @forecast = split("\n", $response->content);
		if (@forecast) {
			$dbh->do("DELETE FROM forecasts WHERE city='$city-$state'") 
				or die ("DB error: $DBI::err ($DBI::errstr)");
			$dbh->do("INSERT INTO forecasts (city,issued,chunk0,chunk1,chunk2,chunk3,chunk4) VALUES "
				."('$city-$state','$forecast[3]','$forecast[5]','$forecast[6]','$forecast[7]','$forecast[8]','$forecast[9]')")
				or die ("DB error: $DBI::err ($DBI::errstr)");
		}
	}
	$dbh->disconnect();
}

&main();

