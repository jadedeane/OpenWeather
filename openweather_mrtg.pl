#!/usr/bin/env perl
# Open Weather 0.22
# Script: openweather_mrtg.pl rev 3
# Developer: Jade E. Deane (jade.deane@gmail.com)
# Purpose: Output information for MRTG.

use strict;

use DBI;
use POSIX qw(strftime);

my %openweather;
my $Configfile = "";
open (CONF,$Configfile) or die "Could not open config file $Configfile: $! \n";
my $code = join ('', <CONF>);
close (CONF);
eval $code;

my $db_type = $openweather{'db_type'};
my $db_username = $openweather{'db_username'};
my $db_password = $openweather{'db_password'};
my $db_hostname = $openweather{'db_hostname'};
my $db_database = $openweather{'db_database'};

my $type = $ARGV[1];

my $dbh;

sub db_error {
    # Output database errors.
    print "Sorry, an error occurred while performing database action(s)!\n<br>$DBI::errstr";
}

sub db_establish { 
    # Establish connection with database.
    my %DBConnectOpts = (PrintError => 0, RaiseError => 0);
    my $DSN = "DBI:$db_type:$db_database:$db_hostname";
    $dbh = DBI->connect($DSN, $db_username, $db_password, \%DBConnectOpts) or db_error;
}

sub get_cycle {
    # Determine current METAR cycle based on UTC HHMM.
    my $time = shift;
	my $query_cycle;
    if (($time >=2345) or ($time <= 044)) { 
        $query_cycle = "00"; 
    } elsif (($time >= 045) and ($time <= 144)) { 
        $query_cycle = "01"; 
    } elsif (($time >= 145) and ($time <= 244)) { 
        $query_cycle = "02"; 
    } elsif (($time >= 245) and ($time <= 344)) { 
        $query_cycle = "03"; 
    } elsif (($time >= 345) and ($time <= 444)) { 
        $query_cycle = "04"; 
    } elsif (($time >= 445) and ($time <= 544)) { 
        $query_cycle = "05"; 
    } elsif (($time >= 545) and ($time <= 644)) { 
        $query_cycle = "06"; 
    } elsif (($time >= 645) and ($time <= 744)) { 
        $query_cycle = "07"; 
    } elsif (($time >= 745) and ($time <= 844)) { 
        $query_cycle = "08"; 
    } elsif (($time >= 845) and ($time <= 944)) { 
        $query_cycle = "09"; 
    } elsif (($time >= 945) and ($time <= 1044)) { 
        $query_cycle = "10"; 
    } elsif (($time >= 1045) and ($time <= 1144)) { 
        $query_cycle = "11"; 
    } elsif (($time >= 1145) and ($time <= 1244)) { 
        $query_cycle = "12"; 
    } elsif (($time >= 1245) and ($time <= 1344)) { 
        $query_cycle = "13"; 
    } elsif (($time >= 1345) and ($time <= 1444)) { 
        $query_cycle = "14"; 
    } elsif (($time >= 1445) and ($time <= 1544)) { 
        $query_cycle = "15"; 
    } elsif (($time >= 1545) and ($time <= 1644)) { 
        $query_cycle = "16"; 
    } elsif (($time >= 1645) and ($time <= 1744)) { 
        $query_cycle = "17"; 
    } elsif (($time >= 1745) and ($time <= 1844)) { 
        $query_cycle = "18"; 
    } elsif (($time >= 1845) and ($time <= 1944)) { 
        $query_cycle = "19"; 
    } elsif (($time >= 1945) and ($time <= 2044)) { 
        $query_cycle = "20"; 
    } elsif (($time >= 2045) and ($time <= 2144)) { 
        $query_cycle = "21"; 
    } elsif (($time >= 2145) and ($time <= 2244)) { 
        $query_cycle = "22"; 
    } elsif (($time >= 2245) and ($time <= 2344)) { 
        $query_cycle = "23"; 
    }
	if ($query_cycle <= 0) {
        $query_cycle = "23Z";
    } elsif ($query_cycle <= 1) {
        $query_cycle = "00Z";
    } elsif ($query_cycle > 1) {		
        $query_cycle--;
        if (($query_cycle >= 1) and ($query_cycle <= 9)) {
            $query_cycle = "0" . $query_cycle."Z";
        } else {
            $query_cycle .= "Z";
        }
    }
    return($query_cycle);
}

sub main {
	my $icao = $ARGV[0];
	my $cycletime = int(strftime "%H%M", gmtime);
	my $query_cycle = get_cycle($cycletime);
	db_establish();
	my @row = $dbh->selectrow_array("SELECT $type FROM reports_cur WHERE site='$icao' AND cycle='$query_cycle'");
	exit if !$row[0];
	$row[0] =~ m#^(M?[0-9][0-9])/(M?[0-9][0-9])#;
	my $temperature = $1;
	$temperature =~ s/M/-/;
	int($temperature);
	$temperature = (9 / 5) * $temperature + 32;
	$temperature = sprintf("%.0f", $temperature);
	if ($temperature < 0) {
		$temperature = abs($temperature);
		print "$temperature\n0\n";
	} elsif ($temperature > 0) {
		print "0\n$temperature\n";
	}
}

&main();