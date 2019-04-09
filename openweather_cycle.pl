#!/usr/bin/env perl
# Open Weather 0.22
# Script: openweather_cycle.pl rev 28
# Developer: Jade E. Deane (jade.deane@gmail.com)
# Purpose: Fetch METAR information.


use strict;

use DBI;
use LWP::UserAgent;
use POSIX qw(strftime);

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

my $debug = 1;
my $use_local = 0;
my $UseDB = 1;
my %Args;
my $now;
my $DBH;

sub TRUE { return 1; }
sub FALSE { return 0; }

# Signal handlers.
$SIG{"INT"}  = \&sighandler;
$SIG{"QUIT"} = \&sighandler;

if ( $UseDB == 1 ) {
	my %DBConnectOpts = (PrintError => 0, RaiseError => 0);
	my $DSN = "DBI:$db_type:$db_database:$db_hostname";
	$DBH = DBI->connect($DSN, $db_username, $db_password, \%DBConnectOpts)
	or die "DB error: $DBI::err ($DBI::errstr)";
}

# Report data structure.
my %MetarReport = (
	"raw_report"  => undef,
	"cycle"       => undef,
	"site"        => undef,
	"date_time"   => undef,
	"modifier"    => undef,  # fishy
	"wind"        => undef,
	"visibility"  => undef,
	"clouds"      => undef,
	"temperature" => undef,
	"pressure"    => undef,
	"remarks"     => undef
);

# Set ALL to 1 if you want to process all weather stations.
my %WeatherReports = ("ALL" => 1,);

# Weather types.
my %WeatherTypes = (
	MI => 'shallow',
	PI => 'partial',
	BC => 'patches',
	DR => 'drizzle',
	BL => 'blowing',
	SH => 'shower(s)',
	TS => 'thunderstorm',
	FZ => 'freezing',
	DZ => 'drizzle',
	RA => 'rain',
	SN => 'snow',
	SG => 'snow grains',
	IC => 'ice crystals',
	PE => 'ice pellets',
	GR => 'hail',
	GS => 'small hail/snow pellets',
	UP => 'unknown precip',
	BR => 'mist',
	FG => 'fog',
	FU => 'smoke',
	VA => 'volcanic ash',
	DU => 'dust',
	SA => 'sand',
	HZ => 'haze',
	PY => 'spray',
	PO => 'dust/sand whirls',
	SQ => 'squalls',
	FC => 'funnel cloud(tornado/waterspout)',
	SS => 'sand storm',
	DS => 'dust storm'
  );

my $_weather_types_pat = join("|", keys(%WeatherTypes));

my %SkyTypes = (
	SKC => "Sky Clear",
	CLR => "Sky Clear",
	SCT => "Scattered",
	BKN => "Broken",
	FEW => "Few",
	OVC => "Solid Overcast",
  );

# Regular expressions.
my $stationRE = '^([A-Z]){1}([A-Z0-9]){3}';
my $timeRE = '^([0-9]{6})Z';
my $windRE = '^(([0-9]{3})|VRB)([0-9]?[0-9]{2})(G[0-9]?[0-9]{2})?KT';
my $visRE = '(([0-9]?[0-9])|(M?1/[0-9]?[0-9]))SM';
my $cloudRE = '^(CLR|BKN|SCT|FEW|OVC)([0-9]{3})?';
my $tempRE = '^(M?[0-9][0-9])/(M?[0-9][0-9])';
my $presRE = '^(A|Q)([0-9]{4})';
my $condRE = '^(-|\\+|VC)?(MI|BC|PR|TS|BL|SH|DR|FZ)?(DZ|RA|SN|SG|IC|PE|GR|GS|UP|BR|FG|FU|VA|SA|HZ|PY|DU|SQ|SS|DS|PO|\\+?FC)+';


# Location of cycle file(s).
my $CycleBaseURL = "http://$noaa_server/pub/data/observations/metar/cycles/";

sub error {
	my $error = shift;
	print $error if defined($error) and $error ne '';
	exit 1;
}

sub END {
	&sighandler;
}

sub sighandler {
	if ($DBH) {
		$DBH->disconnect() or die "DB error: $DBI::err ($DBI::errstr)";
	}
	exit 0;
}

sub reset_report {
	$MetarReport{"raw_report"}  = undef;
	$MetarReport{"site"} = undef;
	$MetarReport{"date_time"} = undef;
	$MetarReport{"modifier"} = undef;  # ?
	$MetarReport{"wind"} = undef;
	$MetarReport{"visibility"} = undef;
	$MetarReport{"clouds"} = undef;
	$MetarReport{"temperature"} = undef;
	$MetarReport{"pressure"} = undef;
	$MetarReport{"condition"} = undef;
	$MetarReport{"remarks"} = undef;
}

sub metar_token_cond {
	my $token = shift;
	if ($token !~ m/$condRE/) {
		return FALSE;
	}  
	$MetarReport{"condition"} = $1.$2.$3;
	return TRUE;
}

sub metar_token_pres { 
	my $token = shift;
	if ($token !~ m/$presRE/) {
		return FALSE;
	}
	$MetarReport{"pressure"} = $token;
	return TRUE;
}

sub metar_token_temp {
	my $token = shift;
	if ($token !~ m/$tempRE/) {
		return FALSE;
	}
	$MetarReport{"temperature"} = $token;
	return TRUE;
}

sub metar_token_cloud {
	my $token = shift;
	if ($token !~ m/$cloudRE/) {
		return FALSE;
	}
	$MetarReport{"clouds"} = $token;
	return TRUE;
}

sub metar_token_vis { 
	my $token = shift;
	if ($token !~ m/$visRE/) {
		return FALSE;
	}
	$MetarReport{"visibility"} = $token;
	return TRUE;
}

sub metar_token_wind {
	my $token = shift;
	if ($token !~ m/$windRE/) {
		return FALSE;
	}
	$MetarReport{"wind"} = $token;
	return TRUE;
}

sub metar_token_station {
	my $token = shift;
	if (($token !~ /$stationRE/) or ($token eq "AUTO")) {
		return FALSE;
	} elsif (($token =~ m/$stationRE/) and (length($token) eq 4)) {
		$MetarReport{"site"} = $token;
		return TRUE;
	}
}

sub metar_token_time {
	my $token = shift;
	if ($token !~ m/$timeRE/) {
		return FALSE;
	}
	$MetarReport{"date_time"} = $token;
	return TRUE;
}

sub metar_parse_token {
	my $token = shift;
	if (metar_token_time($token)) {
		return TRUE;
	} elsif (metar_token_station($token)) {
		return TRUE;
	} elsif (metar_token_wind($token)) {
		return TRUE;
	} elsif (metar_token_vis($token)) {
		return TRUE;
	} elsif (metar_token_cloud($token)) {
		return TRUE;
	} elsif (metar_token_temp($token)) {
		return TRUE;
	} elsif (metar_token_pres($token)) {
		return TRUE;
	} elsif (metar_token_cond($token)) {
		return TRUE;
	}
	return TRUE;
}

sub metar_parse {
	my $report = shift;
	my @TOKENS;
	my ($token, $in_remarks);
	@TOKENS = split(/\s+/, $report);
	while (defined($token = shift(@TOKENS))) {
		metar_parse_token($token);
	}
	if (($UseDB) and ($MetarReport{"site"})) {
		print "Inserting ".$MetarReport{"site"}." ($report)\n" if $debug;
		$DBH->do("INSERT INTO reports_cur "
			."(raw_report,cycle,site,date_time,wind,visibility,clouds,temperature,pressure,"
			." condition,created) VALUES ("
			."'$report',"
			."'".$MetarReport{"cycle"}."',"
			."'".$MetarReport{"site"}."',"
			."'".$MetarReport{"date_time"}."',"
			."'".$MetarReport{"wind"}."',"
			."'".$MetarReport{"visibility"}."',"
			."'".$MetarReport{"clouds"}."',"
			."'".$MetarReport{"temperature"}."',"
			."'".$MetarReport{"pressure"}."',"
			."'".$MetarReport{"condition"}."',"
			."'".$now."')");
	}
	&reset_report();
}

sub get_cycle_file {
	my $time = shift;
	my $cyclefile;
	if (@ARGV[0]) {
		$cyclefile = $ARGV[0];
		$MetarReport{"cycle"} = $cyclefile;
		$cyclefile .= ".TXT";
		return ($cyclefile);
	}
	if (($time >= 2345) or ($time <= 044)) {
		$cyclefile = "00Z";
	} elsif (($time >= 045) and ($time <= 144)) {
		$cyclefile = "01Z";
	} elsif (($time >= 145) and ($time <= 244)) {
		$cyclefile = "02Z";
	} elsif (($time >= 245) and ($time <= 344)) {
		$cyclefile = "03Z";
	} elsif (($time >= 345) and ($time <= 444)) {
		$cyclefile = "04Z";
	} elsif (($time >= 445) and ($time <= 544)) {
		$cyclefile = "05Z";
	} elsif (($time >= 545) and ($time <= 644)) {
		$cyclefile = "06Z";
	} elsif (($time >= 645) and ($time <= 744)) {
		$cyclefile = "07Z";
	} elsif (($time >= 745) and ($time <= 844)) {
		$cyclefile = "08Z";
	} elsif (($time >= 845) and ($time <= 944)) {
		$cyclefile = "09Z";
	} elsif (($time >= 945) and ($time <= 1044)) {
		$cyclefile = "10Z";
	} elsif (($time >= 1045) and ($time <= 1144)) {
		$cyclefile = "11Z";
	} elsif (($time >= 1145) and ($time <= 1244)) {
		$cyclefile = "12Z";
	} elsif (($time >= 1245) and ($time <= 1344)) {
		$cyclefile = "13Z";
	} elsif (($time >= 1345) and ($time <= 1444)) {
		$cyclefile = "14Z";
	} elsif (($time >= 1445) and ($time <= 1544)) {
		$cyclefile = "15Z";
	} elsif (($time >= 1545) and ($time <= 1644)) {
		$cyclefile = "16Z";
	} elsif (($time >= 1645) and ($time <= 1744)) {
		$cyclefile = "17Z";
	} elsif (($time >= 1745) and ($time <= 1844)) {
		$cyclefile = "18Z";
	} elsif (($time >= 1845) and ($time <= 1944)) {
		$cyclefile = "19Z";
	} elsif (($time >= 1945) and ($time <= 2044)) {
		$cyclefile = "20Z";
	} elsif (($time >= 2045) and ($time <= 2144)) {
		$cyclefile = "21Z";
	} elsif (($time >= 2145) and ($time <= 2244)) {
		$cyclefile = "22Z";
	} elsif (($time >= 2245) and ($time <= 2344)) {
		$cyclefile = "23Z";
	}
	$MetarReport{"cycle"} = $cyclefile;
	$cyclefile = $cyclefile.".TXT";
	return $cyclefile;
}

sub get_remote_file {
	my $cycle = shift;
	my $cycle_url = $CycleBaseURL.$cycle;
	print "Attempting to retreive $cycle_url\n" if $debug;
	my $ua = new LWP::UserAgent;
	my $request = new HTTP::Request('GET', $cycle_url);
	my $response = $ua->request($request);
	if ($response->is_success()) {
		return $response->content;
	} else {
		error("Error retrieving $cycle_url, better luck next time.\n");
	}
}

sub main {
	my $cycle_file;
	$now = strftime "%Y-%m-%d %H:%M:%S", gmtime;
	print "Current datetime in UTC: $now\n" if $debug;
	my $cycletime = int(strftime "%H%M", gmtime);
	my $cyclefile = get_cycle_file($cycletime);
	if ($UseDB) {
		print "Removing current cycle dup(s)!\n" if $debug;
		$DBH->do("DELETE FROM reports_cur WHERE cycle='".$MetarReport{"cycle"}."'")
			or die ("DB error: $DBI::err ($DBI::errstr)");
	}
	print "Cycle file for $now is $cyclefile\n" if $debug;
	if ($use_local == 1) {
		print "In Local Mode\n" if $debug;
		open(IN, "<$ARGV[0]") or error("$!\n");
		$/ = undef;
		$cycle_file = <IN>;
		close(IN);
	} else {
		$cycle_file = &get_remote_file(&get_cycle_file($cycletime));
	}
	my @WEATHER_SITES = split("\n\n", $cycle_file);
	foreach my $site (@WEATHER_SITES) {
		my ($date, $report) = split("\n", $site);
		my ($station) = $report =~ m/^(.*?)\s+/;
		$WeatherReports{"ALL"} == 1 ? &metar_parse($report) :
		exists($WeatherReports{$station}) ? &metar_parse($report) :
		next;
	}
}

&main();

exit 0;