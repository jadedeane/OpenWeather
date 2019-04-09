#!/usr/bin/env perl
# Open Weather 0.22
# Script: openweather_query.pl rev 109
# Developer: Jade E. Deane (jade.deane@gmail.com)
# Purpose: CGI to query weather information.

use strict;

use CGI qw(:standard escapeHTML);
use DBI;
use POSIX qw(strftime);
use Math::Trig qw(great_circle_distance deg2rad);
use Astro::Sunrise;

# Config.
my %openweather;
my $Configfile = "";
open (CONF,$Configfile) or die "Could not open config file $Configfile: $! \n";
my $code = join ('', <CONF>);
close (CONF);
eval $code;

# Global items.
my $hostname = $openweather{'hostname'};
my $home_icao = $openweather{'home_icao'};
my $home_state = $openweather{'home_state'};
my $home_zip = $openweather{'home_zip'};
my $dst = $openweather{'dst'};
my $get_forecast = $openweather{'get_forecast'};
my $mrtg = $openweather{'mrtg'};
my $mrtg_sites = $openweather{'mrtg_sites'};
my $raw_prompt = $openweather{'raw_prompt'};
my $images = $openweather{'images'};
my $header = $openweather{'header'};
my $footer = $openweather{'footer'};
my $display_no_report = $openweather{'display_no_report'};
my $db_type = $openweather{'db_type'};
my $db_username = $openweather{'db_username'};
my $db_password = $openweather{'db_password'};
my $db_hostname = $openweather{'db_hostname'};
my $db_database = $openweather{'db_database'};
my $ui = param('ui');
my $range = param('range');
my $metric = param('metric');
my $folder_redir = param('folder_redir');
my $composite_ani = param('composite_ani');
my $nexrad_ani = param('nexrad_ani');
my $raw_report = param('raw_report');
my $int_list = param('list');
my $base_loc = "openweather_query.pl";
my $blobimg = "openweather_blobimg.pl";
my $openweather_version = "0.22";
my $version = "108";

my (
	$query_cycle, $nexrad, $nexrad_i, $error, $dbh, $offset, $site_info, 
	$forecast, $forecast_city, $temp_dongle, $temp_convert, $temp_noti,
	$countries
);

my (@geo_output, @sites_output);

my $cycletime = int(strftime "%H%M", gmtime);
my $utc_c = strftime "%H%M", gmtime;
my $utc_h = int(strftime "%H", gmtime);
my $utc_mm = int(strftime "%M", gmtime);
my $utc_y = int(strftime "%Y", gmtime);
my $utc_m = int(strftime "%m", gmtime); 
my $utc_month = strftime "%B", gmtime;
my $utc_d = int(strftime "%d", gmtime); 
my $utc_day = strftime "%A", gmtime;
my $utc_e = int(strftime "%e", gmtime);
my $utc_s = int(strftime "%S", gmtime);

my %output = (
	"raw_report" => undef,
	"site_info" => "Unknown Site",
	"longitude" => undef,
	"latitude" => undef,
	"date" => undef,
	"sunrise" => undef,
	"sunset" => undef,
	"temperature" => "N/R",
	"temperature_change" => "N/R",
	"dew_point" => "N/R", 
	"relative_humidity" =>"N/R",
	"sky" => "N/R",
	"conditions" => "N/R",
	"wind" => => "N/R",
	"wind_v" => undef,
	"index_desc" => "Feels like:",
	"index" => "N/A",
	"nexrad" => undef,
	"updated" => undef
  );

my %state_names = (
	'AL' => 'Alabama',
	'AK' => 'Alaska',
	'AR' => 'Arkansas',
	'AZ' => 'Airizona',			   
	'CA' => 'California',
	'CO' => 'Colorado',
	'CT' => 'Connecticut',
	'DC' => 'District of Columbia',
	'DE' => 'Delaware',
	'FL' => 'Florida',
	'GA' => 'Georgia',
	'GU' => 'Guam',
	'HI' => 'Hawaii',
	'ID' => 'Idaho',
	'IL' => 'Illinois',
	'IN' => 'Indiana',
	'IA' => 'Iowa',
	'KS' => 'Kansas',
	'KY' => 'Kentucky',
	'LA' => 'Louisiana',
	'ME' => 'Maine',
	'MD' => 'Maryland',
	'MA' => 'Massachusetts',
	'MI' => 'Michigan',
	'MN' => 'Minnesota',
	'MS' => 'Mississippi',
	'MO' => 'Missouri',
	'MT' => 'Montana',
	'NE' => 'Nebraska',
	'NV' => 'Nevada',
	'NH' => 'New Hampshire',
	'NJ' => 'New Jersey',
	'NM' => 'New Mexico',
	'NY' => 'New York',
	'NC' => 'North Carolina',
	'ND' => 'North Dakota',
	'OH' => 'Ohio',
	'OK' => 'Oklahoma',
	'OR' => 'Oregon',
	'PA' => 'Pennsylvania',
	'RI' => 'Rhode Island',
	'SC' => 'South Carolina',
	'SD' => 'South Dakota',
	'TN' => 'Tennessee',
	'TX' => 'Texas',
	'UT' => 'Utah',
	'VT' => 'Vermont',
	'VA' => 'Virgina',
	'WA' => 'Washington',
	'WV' => 'West Virgina',
	'WI' => 'Wisconsin',
	'WY' => 'Wyoming'
);
my $state_names_pat = join("|", keys(%state_names));

sub db_error {
    # Output database errors.
    $error = "Sorry, an error occurred while performing database action(s)!\n<br>$DBI::errstr";
    disem();
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

sub previous_cycle {
	# Determine previous cycle.
	$query_cycle =~ s/Z//;
	int $query_cycle;
	my $previous_cycle;
	if ($query_cycle <= 0) {
		$previous_cycle = 23;
	} else {
		$previous_cycle = $query_cycle - 1;
	}
	if (($previous_cycle >= 0) and ($previous_cycle <= 9)) {
		$previous_cycle = "0" . $previous_cycle . "Z";
	} else {
		$previous_cycle .= "Z";
	}	
	return ($previous_cycle);
}

sub day_time {
    # Determine information about the day.
    my $dt_h;
    my $longitude = $_[0];
    my $latitude = $_[1];
    my @longitude_l = split("-", $longitude);
    my @latitude_l = split("-", $latitude);
    $longitude = $longitude_l[0];
    $latitude = $latitude_l[0];
    int($longitude);
    int($latitude);
    my $tz_zone = zone($longitude, $latitude);
	return(0) if !$tz_zone;
    my @row = $dbh->selectrow_array("SELECT offset FROM tz WHERE zone='$tz_zone'");
    int($offset = $row[0]);
	$offset-- if $dst;
    int($offset);
    if ($offset != abs($offset)) {
        $dt_h = ($utc_h - abs($offset));
        if ($dt_h != abs($dt_h)) {
        $dt_h = ($dt_h + 24);
        }
    } elsif ($offset = abs($offset)) {
        $dt_h = ($utc_h + $offset);
        if ($dt_h >= 16) {
            $dt_h = ($dt_h - 24);
		}
	}
	if ($longitude = abs($longitude)) {
		$longitude = ($longitude - ($longitude * 2));
	}	
	my ($sunrise, $sunset) = sunrise($utc_y, $utc_m, $utc_d, $longitude, $latitude, $offset);
	$sunset =~ /(\w\w)?:?(\w\w)?/;
	$sunset = ($1 - 12) . ":" . $2;
	$output{"sunrise"} = "Sunrise: $sunrise" . "am localtime";
	$output{"sunset"} = "Sunset: $sunset" . "pm localtime";
    return(1);
}

sub zone {
    # Determine time zone.
    my $tz_zone;
    my ($longitude, $latitude) = @_;
    int($longitude);
    int($latitude);
    if (($longitude >= 60) and ($longitude < 75)) {
        $tz_zone = "Q";
    } elsif (($longitude >= 75) and ($longitude < 90)) {
        $tz_zone = "R";
    } elsif (($longitude >= 90) and ($longitude < 105)) {
        $tz_zone = "S";
    } elsif (($longitude >= 105) and ($longitude < 130)) {
        $tz_zone = "T";
    } elsif (($longitude >= 135) and ($longitude < 180)) {
        $tz_zone = "V";
    } elsif (($longitude < 60) or ($longitude > 178) or ($latitude < 24) or ($latitude > 75)) {
        #$error = "Sorry, the site returned is not in the northwestern hemisphere!";
		#disem();
		return();
    }
    return($tz_zone);
}

sub temp_convert {
	my $type = shift;
	my $temperature = shift;
	if ($type eq 1) {
		$temperature = (9 / 5) * $temperature + 32;
	} elsif ($type eq 2) {
		$temperature = (5 / 9) * $temperature - 32;	
	}
	$temperature = sprintf("%.1f", $temperature);
	return($temperature);	
}

sub temp_index {
	# Determine heat index or wind chill.
    my ($temperature, $RHp, $WS) = @_;
    my ($index_t, $index_v);
    if ((($temperature >= 70) and $temp_convert) or (($temperature >= 21.1) and !$temp_convert)) {
		$index_t = "Heat Index";
        my $HIf = -42.379
			+ 2.04901523 * $temperature
			+ 10.14333127 * $RHp
			- 0.22475541 * $temperature * $RHp
			- 6.83783 * 10 **-3 * $temperature **2
			- 5.481717 * 10 **-2 * $RHp **2
			+ 1.22874 * 10 **-3 * $temperature **2 * $RHp
			+ 8.5282 * 10 **-4 * $temperature * $RHp **2
			- 1.99 * 10 **-6 * $temperature **2 * $RHp **2;
        $index_v = $HIf = sprintf("%.1f", $HIf);
    } elsif ((($temperature <= 50) and $temp_convert and ($WS >= 1)) or (($temperature <= 10) and !$temp_convert and ($WS >= 1))) {
		$index_t = "Wind Chill";
		my $WCf = 35.74 + 0.6215 * $temperature - 35.75 * ($WS **0.16) + 0.4275 * $temperature * ($WS **0.16);
        $index_v = $WCf = sprintf("%1.f", $WCf);          
    } else {
		$index_t = "Feels Like";
        $index_v = $temperature;
    }	
    return($index_t, $index_v);
}

sub relative_humidity {
	# Determine relative humidity.
	my $temperature = $_[0];
	my $dew_point = $_[1];
	$temperature = temp_convert(2, $temperature) if $temp_convert;
	$dew_point = temp_convert(2, $dew_point) if $temp_convert;
    my $Es = 6.11 * 10.0 **(7.5 * $temperature / (237.7 + $temperature));
    my $E = 6.11 * 10.0 **(7.5 * $dew_point / (237.7 + $dew_point));  
    my $RHp = ($E / $Es) * 100;
    $RHp = sprintf("%.1f", $RHp);
    return($RHp);
}

sub wind {
	# Determine wind conditions.
    $_[0] =~ /(\w\w\w)(\d?\d\d)/;
    my $dir_deg = $1;
    my $wind_speed = $2;
	$wind_speed = $wind_speed * 1.1508 unless $metric;
    $wind_speed = sprintf("%.1f", $wind_speed);
    return($dir_deg, $wind_speed);
}

sub metar_parse {
    # Parse METAR elements.
    my $metar_string = shift;
    my ($dir_eng, $wt_a, $wt_n, $engl, $agl);
    my %weather_types = (
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
    my $weather_types_pat = join("|", keys(%weather_types));
    if ($metar_string =~ /.*?KT$/i) {
        # Wind information.
        my ($dir_deg, $wind_speed) = wind($metar_string);
        $output{"wind_v"} = $wind_speed;
        if ($dir_deg =~ /VRB/i) {
            $dir_eng = "Variable";
        } elsif (($dir_deg >= 0) and ($dir_deg < 15)) {
            $dir_eng = "N";
        } elsif (($dir_deg >= 15) and ($dir_deg < 30)) {
            $dir_eng = "N/NE";
        } elsif (($dir_deg >= 30) and ($dir_deg < 60)) {
            $dir_eng = "NE";
        } elsif (($dir_deg >= 60) and ($dir_deg < 75)) {
            $dir_eng = "E/NE";
        } elsif (($dir_deg >= 75) and ($dir_deg < 105)) {
            $dir_eng = "E";
        } elsif (($dir_deg >= 105) and ($dir_deg < 120)) {
            $dir_eng = "E/SE";
        } elsif (($dir_deg >= 120) and ($dir_deg < 150)) {
            $dir_eng = "SE";
        } elsif (($dir_deg >= 150) and ($dir_deg < 165)) {
            $dir_eng = "S/SE";
        } elsif (($dir_deg >= 165) and ($dir_deg < 195)) {
            $dir_eng = "S";
        } elsif (($dir_deg >= 195) and ($dir_deg < 210)) {
            $dir_eng = "S/SW";
        } elsif (($dir_deg >= 210) and ($dir_deg < 240)) {
            $dir_eng = "SW";  
        } elsif (($dir_deg >= 240) and ($dir_deg < 265)) {
            $dir_eng = "W/SW";
        } elsif (($dir_deg >= 265) and ($dir_deg < 285)) {
            $dir_eng = "W";
        } elsif (($dir_deg >= 285) and ($dir_deg < 300)) {
            $dir_eng = "W/NW";
        } elsif (($dir_deg >= 300) and ($dir_deg < 330)) {
            $dir_eng = "NW";
        } elsif (($dir_deg >= 330) and ($dir_deg < 345)) {
            $dir_eng = "N/NW";
        } else {
            $dir_eng = "Unknown direction";
        }
		my $windf;
        if ($wind_speed >= 1) { 
			$windf = "$dir_eng (" . $dir_deg . "\&deg) at $wind_speed ";
			if ($metric) {
				$windf .= "Kts";
			} else {
				$windf .= "Mph";
			}
			$output{"wind"} = $windf;
        } else {
            $output{"wind"} = "Calm";
        }
        return();
    } elsif ($metar_string =~ /^(-|\+)?(VC)?($weather_types_pat)+/) {
        # Determine weather condition(s).
        my $qual = $1;
        my $addlqual = $2;
        if (defined $qual) {
            if ($qual eq "-") {
                $engl = "Light";
            } elsif ($qual eq "+") {
                $engl = "Heavy";
            } else {
                $engl = "Moderate";
            }
        } else {
            $engl = "Moderate";
        }
        $wt_a = 0;
        while ($metar_string =~ /($weather_types_pat)/gi ) {
            $wt_a++;
            if ($wt_a <=1 ) {
                $wt_n = " ";
            } elsif ($wt_a >= 2) {
                $wt_n = ", ";
            }
            $engl .= $wt_n . $weather_types{$1};
        }
        if (defined $addlqual) {
            if ( $addlqual eq "VC" ) {
                $engl .= " in vicinity";
            }
        }
        $engl =~ s/^\s//gio;
        $engl =~ s/\s\s/ /gio;
        $output{"conditions"} = "$engl";
        return();
    } elsif ($metar_string eq "SKC" or $metar_string eq "CLR") {
        # Determine sky condition.
        $output{"sky"} = "Clear";
        return();
    } elsif ($metar_string =~ /^(FEW|SCT|BKN|OVC|SKC|CLR)(\d\d\d)?(CB|TCU)?$/i) {
        my %sky_types = (
            SKC => "Clear",
            CLR => "Clear",
            SCT => "Scattered clouds",
            BKN => "Broken clouds",
            FEW => "Few clouds",
            OVC => "Solid overcast",
        );	
        $engl = $sky_types{$1};
        if (defined $3) {
            if ($3 eq "TCU") {
                $engl .= " towering cumulus";
            } elsif ($3 eq "CB") {
                $engl .= " cumulonimbus";
            }
        }
        if ($2 ne "") {
            $agl = int($2) * 100;
			$agl = $agl * 0.3048 if $metric;
            $engl .= " at $agl";
			if ($metric) {
				$engl .= "m";
			} else {
				$engl .= "ft";	
			}
        }
        $output{"sky"} = "$engl";
        return();
    } elsif ($metar_string =~ m#^(M?[0-9][0-9])/(M?[0-9][0-9])#) {
        # Determine temperature information.
		my $temperature = $1; 
		my $dew_point = $2;
		my ($previous_temperature, $temperature_change);
		$temperature =~ s/M/-/;
		int($temperature);
		$dew_point =~ s/M/-/;
		int($dew_point);
        $temperature = temp_convert(1, $temperature) if $temp_convert;
		#$temperature = sprintf("%.1f", $temperature) if !$temp_convert;
        $dew_point = temp_convert(1, $dew_point) if $temp_convert;
		#$dew_point = sprintf("%.1f", $dew_point) if !$temp_convert;
        my $RHp = relative_humidity($temperature, $dew_point);
        my ($index_t, $index_v) = temp_index($temperature, $RHp, $output{"wind_v"});
        $output{"temperature"} = $temperature . $temp_noti;
        $output{"temperature_v"} = $temperature;
        $output{"dew_point"} = $dew_point . $temp_noti;
        $output{"relative_humidity"} = "$RHp%";
		$output{"index_desc"} = $index_t;
        $output{"index"} = $index_v . $temp_noti;
		my $previous_cycle = previous_cycle();
		my @row = $dbh->selectrow_array("SELECT temperature FROM reports_cur WHERE site='$ui' AND cycle='$previous_cycle'");
		if (@row[0]) {
			$row[0] =~ m#^(M?[0-9][0-9])/(M?[0-9][0-9])#;
			$previous_temperature = $1;
			$previous_temperature =~ s/M/-/;
			int($previous_temperature);
			$previous_temperature = temp_convert(1, $previous_temperature) if $temp_convert;
			$temperature_change = abs($temperature - $previous_temperature);
			$temperature_change = sprintf("%.1f", $temperature_change);
		} else {
			$temperature_change = 0;
			$previous_temperature = $temperature;	
		}
		if ($previous_temperature > $temperature) {
			$output{"temperature_change"} = "Down " . $temperature_change . "\&deg from " . $previous_temperature . $temp_noti;
			if ((($temperature_change > 4) and $temp_convert) or (($temperature_change > 3) and !$temperature_change)) {
				$temp_dongle = "<img src=\"images/temp_down_sharp.png\">";
			} else {
				$temp_dongle = "<img src=\"images/temp_down.png\">";
			}
		} elsif ($previous_temperature < $temperature) {
			$output{"temperature_change"} = "Up " . $temperature_change . "\&deg from " . $previous_temperature . $temp_noti ;
			if ((($temperature_change > 4) and $temp_convert) or (($temperature_change > 3) and !$temperature_change)) {
				$temp_dongle = "<img src=\"images/temp_up_sharp.png\">";
			} else {
				$temp_dongle = "<img src=\"images/temp_up.png\">";
			}
		} else {
			$output{"temperature_change"} = "Unchanged";
			$temp_dongle = "<img src=\"images/temp_no_change.png\">";	
		}
        return();
    }
}

sub countries {
	my $sql = "SELECT DISTINCT country FROM si";
	my $sth = $dbh->prepare ($sql);
	$sth->execute();
	while (my @row = $sth->fetchrow_array) {
		$countries .= $row[0] . "|";
	}
	$sth->finish();
	chop($countries);
}

sub build_countries {
	db_establish();
	print "<table>\n<tr><td>";
	print "<a href=\"$base_loc?folder_redir=international\&list=All\">All</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=A\">A</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=B\">B</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=C\">C</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=D\">D</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=E\">E</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=F\">F</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=G\">G</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=H\">H</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=I\">I</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=J\">J</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=K\">K</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=L\">L</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=M\">M</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=N\">N</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=O\">O</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=P\">P</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=Q\">Q</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=R\">R</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=S\">S</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=T\">T</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=U\">U</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=V\">V</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=W\">W</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=X\">X</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=Y\">Y</a> | ";
	print "<a href=\"$base_loc?folder_redir=international\&list=Z\">Z</a> | ";
	print "<br><br></td></tr>";
	return if !$int_list;
	$int_list = undef if $int_list eq "All";
	my $sql = "SELECT DISTINCT country FROM si WHERE country LIKE '" . $int_list . "%' ORDER BY country";
	my $sth = $dbh->prepare ($sql);
	$sth->execute();
	while (my @row = $sth->fetchrow_array) {
		print "<tr><td><img src=\"images/dot.png\" border=\"0\" height=\"10\" width=\"10\">\&nbsp\;<a href=\"$base_loc?ui=$row[0]\">$row[0]</a></td></tr>";	
	}
	$sth->finish();
	print "</table>\n";
}

sub sites {
	push(@sites_output, "<b>Sites in $ui:</b>\n<table>\n");
	my $sql = "SELECT icao,place,country FROM si WHERE country LIKE '$ui' ORDER BY place";
	my $sth = $dbh->prepare ($sql);
	$sth->execute();
	while (my @row = $sth->fetchrow_array) {
		push(@sites_output, 
			"<tr>\n<td><img src=\"images/dot.png\" border=\"0\" height=\"10\" width=\"10\">\&nbsp\;"
			."<a href=\"$base_loc?ui=$row[0]\">$row[0]</a></td>\n"
			."<td>$row[1], $row[2].\&nbsp\;\&nbsp\;</td>\n</tr>\n"
		);
	}
	$sth->finish();
	push(@sites_output, "</table>\n<br>");
	disem();
}

sub site {
    # Prepare site report.
    if (!icao_query()) {
        $error = "Sorry, $ui was not found in the list of sites!";
        disem();
    }
    if (($nexrad) and ($nexrad_i)) {
        disem();
    } elsif (($nexrad) and (!$nexrad_i)) {
        $error = "Sorry, this site does not contain NEXRAD information!";
        disem();
    } else { 
        if (!site_query() >= 1) {
			#my $previous_cycle = previous_cycle();
			if ($display_no_report) {
				$error = "Sorry, no report was found for this site.  Perhaps the site did not report?<br>\n";
				disem();
			}
			#$error .= "Would you like to query the <a href=\"$base_loc?ui=$ui\&cycle=$previous_cycle\">previous<\/a> cycle for $ui or <a href=\"$base_loc?ui=$ui\">refresh</a>?<br>\n";
        }
    }
	disem();
}

sub icao_query {
    # Query site information.
	my @row = $dbh->selectrow_array("SELECT place,state,country,s_longitude,s_latitude FROM si WHERE icao='$ui'");
	if (@row) {
        my $place = $row[0];
        my $state = $row[1];
        my $country = $row[2];
        my $longitude = $row[3];
        my $latitude = $row[4];
		$output{"longitude"} = $longitude;
		$output{"latitude"} = $latitude;
		$forecast = 1;
        day_time($longitude, $latitude);
        if ($place =~ /NEXRAD/i) {
            $place =~ s/NEXRAD//gi;
            chop($place);
            $nexrad_i = 1;
        }
        my @placei = split(",", $place);
        if ($state =~ /($state_names_pat)/g) {
            $state = $state_names{$1};
        }
		my @forecast_city_temp = split(" ", $placei[0]);
		foreach (@forecast_city_temp) {
			$_ = lc($_);
			$forecast_city .= $_ . "_";
		}
		$forecast_city =~ s/\///g;
		$forecast_city =~ s/__/_/g; 
		chop($forecast_city);
		$forecast_city .= "-$row[1]";
		lc($forecast_city);
		my $cityname;
		$cityname = "NEXRAD - " if $nexrad;
		$cityname .= $placei[0];
		$cityname .= ", $state" if $state;
		$cityname .= ", $row[2]";
        $site_info = "<table cellspacing=\"1\"><tr><td class=\"cityname\">$cityname</td></tr></table>"
			."<table><tr><td class=\"cityname_cont\">$placei[1]</td></tr><tr><td class=\"date\"><br>" . $output{"date"} . "</td></tr>"
			."<tr><td>" . $output{"sunrise"} . "</td></tr><tr><td>" . $output{"sunset"} . "</td></tr></table>";
		$output{"site_info"} = $site_info;
		geo();
		return(1);
	} else {
		return(0);
	}
}

sub date_time {
	my $foo = shift;
	$foo =~ /([0-9]{2})([0-9]{2})([0-9]{2})/;
	my $date_time = $2 . ":" . $3;
	return($date_time);
}

sub site_query {
    # Query report information.
    my @row = $dbh->selectrow_array("SELECT wind,visibility,clouds,temperature,pressure,condition,date_time,raw_report,created FROM reports_cur WHERE cycle='$query_cycle' AND site='$ui'");
	$output{"raw_report"} = $row[7];
	$row[7] eq undef;
	if (@row) {
		foreach (@row) {
			metar_parse($_);
		}
		my $date_time = date_time($row[6]);
		my $inserted = $row[8];
		$output{"updated"} = "Observation: $date_time<br>Inserted: $inserted<br>METAR cycle: " . $query_cycle . "Z";
		return(1);
	} else {
		$query_cycle = previous_cycle();
		my @row = $dbh->selectrow_array("SELECT wind,visibility,clouds,temperature,pressure,condition,date_time,raw_report,created FROM reports_cur WHERE cycle='$query_cycle' AND site='$ui'");
		$output{"raw_report"} = $row[7];
		$row[7] eq undef;
		if (@row) {
			foreach (@row) {
				metar_parse($_);
			}
			my $date_time = date_time($row[6]);
			my $inserted = $row[8];
			$output{"updated"} = "Observation: $date_time<br>Inserted: $row[8]<br>METAR cycle: " . $query_cycle . "Z";
			return(1);
		} else {
			return(0);
		}
	}
}

sub get_distance {
    # Determine distance between points of longitude and latitude.
    my ($P1Long, $P1Lat, $P2Long, $P2Lat) = @_;
    my @P1 = (deg2rad($P1Long), deg2rad(90 - $P1Lat));
    my @P2 = (deg2rad($P2Long), deg2rad(90 - $P2Lat));
    return great_circle_distance(@P1, @P2, 3954);
}

sub si_ll {
    # Clean up longitude and latitude.
    my ($longitude, $latitude) = @_;
    if ($longitude =~ /(\d\d\d)-(\d\d)-(\d\d)(\w{0,1})/) {
        $longitude = (($4 EQ "E") ? "-" : "" ) . ($1 + $2/60 + $3/3600);
    } elsif ($longitude =~ /(\d\d\d)-(\d\d)(\w)/) {
        $longitude = (($3 EQ "E") ? "-" : "" ) . ($1 + $2/60);
    }
    if ($latitude =~ /(\d\d)-(\d\d)-(\d\d)(\w)/) {
        $latitude = (($4 EQ "S") ? "-" : "") . ($1 + $2/60 + $3/3600);
    } elsif ($latitude =~ /(\d\d)-(\d\d)(\w)/) {
        $latitude = (($3 EQ "S") ? "-" : "") . ($1 + $2/60);
    }
    return($longitude, $latitude);
}

sub nexrad_ani {
    # Prepare NEXRAD information.
    my $s;
	my $nexrad_b = $nexrad;
	$nexrad_b =~ s/DS.//;
    print "\n<script language=\"javascript\">\n";
    if (($utc_mm >= 0) and ($utc_mm <= 9)) {
        $s = 10;
    } elsif (($utc_mm >= 10) and ($utc_mm <= 19)) {
        $s = 20;
    } elsif (($utc_mm >= 20) and ($utc_mm <= 29)) {   
        $s = 30;
    } elsif (($utc_mm >= 30) and ($utc_mm <= 39)) {
        $s = 40;
    } elsif (($utc_mm >= 40) and ($utc_mm <= 49)) {
        $s = 50;
    } elsif (($utc_mm >= 50) and ($utc_mm <= 59)) {
        $s = 0;
    }
    int($s);
    my $w = 0;
    while ($w <= 5) {
        if ($s > 50) {
            $s = 0;
        }
        print "\tvar img$w = new Image()\;\n"
            ."\timg$w.src = \"nexrad/$ui" . "_" . $nexrad . "_latest_$s.png\"\;\n";
			#openweather_blobimg.pl?loc=KESX&rtype=p19r0&cnum=20
			#."\timg$w.src = \"$blobimg?loc=$ui" . "&rtype=$nexrad_b" ."&cnum=$s\"\;\n";
        $s = $s + 10;
        $w++;
    }
    print "\tvar i = 0\;\n"
        ."\tvar nbImg = 5\;\n"
        ."\tfunction animate() \{\n"
        ."\t\tdocument.images[0].src = eval(\"img\" + i ).src\;\n"
        ."\t\ti++\;\n"
        ."\t\tif (i == nbImg) i=0\;\n"
        ."\t\tfoo = setTimeout(\"animate()\;\", 450)\;\n"
        ."\t\}\n\n</script>\n";
	return();
}

sub geo {
    # Return distance information.
    my $nexrad_range = 155;
    if ($ui =~ /[0-9]{5}/) {
        # Determine if a site is within $range miles of a zip code.
        my ($Zip, $MAX_DISTANCE) = @_;
        my @row = $dbh->selectrow_array("SELECT longitude, latitude FROM zip WHERE zip_code='$Zip'");
        my $ZipLong = $row[0];
        my $ZipLat = $row[1];
        if ((!$ZipLong) or (!$ZipLat))  {
            $error = "Sorry, that US Zip Code was not found!<br>\n";
        disem();
        }
        push(@geo_output, "<b>Sites within $range miles of US Zip Code $ui:</b>\n<table>\n");
        my $sql = "SELECT icao,s_longitude,s_latitude,place,state,country FROM si WHERE country='United States' ORDER BY state,place";
        my $sth = $dbh->prepare ($sql);
        $sth->execute();
		my $dk = $ui . $utc_d . $utc_m . $utc_y . $utc_h . $utc_mm . $utc_s;
        while (my @row = $sth->fetchrow_array) {
            my ($station_longitude, $station_latitude) = si_ll($row[1], $row[2]);
            my $distance = get_distance($ZipLong,$ZipLat, $station_longitude, $station_latitude);
            if ($distance < $MAX_DISTANCE) {
                $distance = sprintf("%.1f", $distance);
				$dbh->do("INSERT INTO distance_temp (dk,icao,distance,place,state) VALUES ('$dk','$row[0]','$distance',\"$row[3]\",'$row[4]')");
			}
		}
		$sth->finish();
		my $sql = "SELECT dk,icao,distance,place,state FROM distance_temp WHERE dk='$dk' and distance < $MAX_DISTANCE ORDER BY distance,place";
		my $sth = $dbh->prepare ($sql);
		$sth->execute();
		while (my @row = $sth->fetchrow_array) {
			my $nexrad = "";
			my $url = "$base_loc?ui=$row[1]";
			if ($row[3] =~ /NEXRAD/i) {
				$row[3] =~ s/nexrad/<a href=\"$base_loc\?ui=$row[1]\&nexrad=DS.p19r0\">NEXRAD<\/a>/gi;
			}
			my $dot;
			#if (forecast($row[3], $row[4])) {
			#	$dot = "images/bluedot.png";
			#} else {
			#	$dot = "images/dot.png";
			#}
			$dot = "images/dot.png";
			push(@geo_output, 
				"<tr>\n<td><img src=\"$dot\" border=\"0\" height=\"10\" width=\"10\">\&nbsp\;"
				."<a href=\"$url\">$row[1]</a></td>\n"
				."<td>$row[3], $row[4].\&nbsp\;\&nbsp\;</td>\n"
				."<td>"
				."Estimated distance is approximately $row[2] miles.</td>\n</tr>\n"
			);
        }
		$sth->finish();
		$dbh->do("DELETE FROM distance_temp WHERE dk='$dk'");
		my $range_l = $range - 10;
		my $range_m = $range + 10;
        push(@geo_output, 
			"</table>\n<br>"
			."Range: <a href=\"$base_loc?ui=$ui\&range=$range_m\">increase</a> or <a href=\"$base_loc?ui=$ui\&range=$range_l\">decrease</a>.<br><br>"
		);
        disem();
	} elsif ((length($ui) eq 2) and ($ui =~ /$state_names_pat/i)) {
		my $sql = "SELECT icao,place,state,country FROM si WHERE country='United States' AND state='$ui' ORDER BY place";
        my $sth = $dbh->prepare ($sql);
        $sth->execute();
		$ui =~ /($state_names_pat)/;
		my $state = $state_names{$1};
		my $state_lc = lc($ui);
		push(@geo_output, "<img src=\"images/flags/$state_lc.jpg\" height=\"40\" width=\"60\" border=\"0\"><br><br><b>Sites within $state:</b>\n<table>\n");
        while (my @row = $sth->fetchrow_array) {
			if ($row[1] =~ /NEXRAD/i) {
				$row[1]	=~ s/nexrad/<a href=\"$base_loc\?ui=$row[0]\&nexrad=DS.p19r0\">NEXRAD<\/a>/gi;
			}
			my $dot;
			#if (forecast($row[1], $row[2])) {
			#	$dot = "images/bluedot.png";
			#} else {
			#	$dot = "images/dot.png";
			#}
			$dot = "images/dot.png";
			push(@geo_output, 
				"<tr>\n<td><img src=\"$dot\" border=\"0\" height=\"10\" width=\"10\">\&nbsp\;"
				."<a href=\"$base_loc?ui=$row[0]\">$row[0]</a></td>\n"
				."<td>$row[1], $row[2], $row[3].\&nbsp\;\&nbsp\;</td>\n</tr>\n"
			);
		}
		$sth->finish();
		push(@geo_output, "</table>\n<br>\n<br><br>\n");
		disem();	
    } elsif ($ui =~ /[A-Z]{1,1}[A-Z0-9]{3,3}/) {
        # Determine if a NEXRAD station is within $nexrad_range miles of a site.
        $output{"nexrad"} = "<table border=\"0\" cellspacing=\"0\" cellpadding=\"0\" width=\"235\">\n"
          ."\t\t<tr>\n"
          ."\t\t\t<td cellspacing=\"1.5\" cellpadding=\"1.5\" valign=\"bottom\" class=\"smallheader\">\n"
          ."\t\t\t\tNEXRAD Radar Sites:"
          ."\t\t\t</td>\n"   
          ."\t\t</tr>\n"
          ."\t</table>\n"
          ."\t<table>\n";
        my @row = $dbh->selectrow_array("SELECT icao,s_longitude,s_latitude FROM si WHERE icao='$ui'");
        my ($station_longitude, $station_latitude) = si_ll($row[1], $row[2]);
        my $sql = "SELECT icao,place,state,country,s_longitude,s_latitude FROM si WHERE place LIKE '%nexrad%' ORDER BY place,state";
        my $sth = $dbh->prepare ($sql);
        $sth->execute();
		my $dk = $ui . $utc_d . $utc_m . $utc_y . $utc_h . $utc_mm . $utc_s;
        while (my @row = $sth->fetchrow_array) {
            my ($nexrad_longitude, $nexrad_latitude) = si_ll($row[4], $row[5]);
            my $distance = get_distance($station_longitude, $station_latitude, $nexrad_longitude, $nexrad_latitude);
            $distance = sprintf("%.1f", $distance);
			if ($distance < $nexrad_range) {
				$dbh->do("INSERT INTO distance_temp (dk,icao,distance,place,state) VALUES ('$dk','$row[0]','$distance',\"$row[1]\",'$row[2]')");
			}
        }
		$sth->finish();
		my $sql = "SELECT dk,icao,distance,place,state FROM distance_temp WHERE dk='$dk' and distance < $nexrad_range ORDER BY distance";
		my $sth = $dbh->prepare ($sql);
		$sth->execute();
		while (my @row = $sth->fetchrow_array) {
			$output{"nexrad"} .=
				"\t\t<tr>\n\t\t\t<td>\n\t\t\t\t<img src=\"images/dot.png\" border=\"0\" height=\"10\" width=\"10\">\&nbsp\;"
				."<a href=\"$base_loc?\&ui=$row[1]&nexrad=DS.p19r0\">$row[1]</a>\n\t\t\t</td>\n"
				."\t\t\t<td>\n\t\t\t\t$row[3], $row[4].\&nbsp\;\&nbsp\;\n\t\t\t</td>";
		}
		$sth->finish();
        $output{"nexrad"} .= "\n\t\t</tr>\n\t</table>"; 
		$dbh->do("DELETE FROM distance_temp WHERE dk='$dk'");       
    }
}

sub forecast {
	if ($_[0] and $_[1]) {
		my $forecast_city;
		my $place = $_[0];
		my $state = $_[1];
		my $state_abv = $_[1];
		my @placei = split(",", $place);
        if ($state =~ /($state_names_pat)/g) {
            $state = $state_names{$1};
        }
		my @forecast_city_temp = split(" ", $placei[0]);
		foreach (@forecast_city_temp) {
			lc($_);
			$forecast_city .= $_ . "_";
		}
		$forecast_city =~ s/\///g;
		$forecast_city =~ s/__/_/g; 
		$forecast_city =~ s/_city//ig;
		chop($forecast_city);
		$forecast_city .= "-$state_abv";
		lc($forecast_city);
		my @row = $dbh->selectrow_array("SELECT city,issued FROM forecasts WHERE city='$forecast_city'");
		if ($row[0] and $row[1]) {
			return("1");
		} else {
			return("0");
		}
	} else {
		if ($ui eq "KBMI") {
			$forecast_city = "peoria-il";
		}
		my @row = $dbh->selectrow_array("SELECT chunk0,chunk1,chunk2,chunk3,chunk4,issued FROM forecasts WHERE city='$forecast_city'");
		my (@slot0, @slot1, @slot2, @slot3, @slot4);
		my $issued = $row[5];
		my $i = 0;
		$slot0[1] = 0;
		$slot1[1] = 0;
		$slot2[1] = 0;
		$slot3[1] = 0;
		$slot4[1] = 0;
		foreach my $elem (@row) {
			my $tempp;
			$elem =~ s/\.//g;
			$elem =~ s/,//g;
			$elem =~ s/night/Night/i;
			$elem =~ s/high/High/g;
			$elem =~ s/low/Low/g;
			if ($elem =~ /(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday){1}\s*(night)*/i) {
				my $weekday = $1 . "<br>";
				my $night = " " . $2;
				$weekday .= $night if ($elem =~ /night/i);
				$weekday .= "<br>" unless ($elem =~ /night/i);
				$slot0[0] = "$weekday" if $i eq 0;
				$slot1[0] = "$weekday" if $i eq 1;
				$slot2[0] = "$weekday" if $i eq 2;
				$slot3[0] = "$weekday" if $i eq 3;
				$slot4[0] = "$weekday" if $i eq 4;
			}
			if ($elem =~ /([0-9]{1,3})(%{1})/) {
				$slot0[1] = $1 if $i eq 0;
				$slot1[1] = $1 if $i eq 1;
				$slot2[1] = $1 if $i eq 2;
				$slot3[1] = $1 if $i eq 3;
				$slot4[1] = $1 if $i eq 4;
			}
			if ($elem =~ /(high|low{1})\s*(-)?([0-9]{1,3})/i) {
				$tempp = $2 . $3;
				int($tempp);
				$tempp = temp_convert(2, $tempp) unless $temp_convert;
				$slot0[2] = "$1 $tempp" if $i eq 0;
				$slot1[2] = "$1 $tempp" if $i eq 1;
				$slot2[2] = "$1 $tempp" if $i eq 2;
				$slot3[2] = "$1 $tempp" if $i eq 3;
				$slot4[2] = "$1 $tempp" if $i eq 4;
			}
			if ($elem =~ /(sunny|fair|partly sunny|cloudy|partly cloudy|mostly cloudy|thunderstorm|showers|windy|rain|snow|flurries)/i) {
				$slot0[4] = $1 if $i eq 0;
				$slot1[4] = $1 if $i eq 1;
				$slot2[4] = $1 if $i eq 2;
				$slot3[4] = $1 if $i eq 3;
				$slot4[4] = $1 if $i eq 4;
				my $image = $1;
				$image =~ s/\s/_/;
				$slot0[3] = "images/conditions/" . lc($image) . ".png" if $i eq 0;	
				$slot1[3] = "images/conditions/" . lc($image) . ".png" if $i eq 1;
				$slot2[3] = "images/conditions/" . lc($image) . ".png" if $i eq 2;
				$slot3[3] = "images/conditions/" . lc($image) . ".png" if $i eq 3;
				$slot4[3] = "images/conditions/" . lc($image) . ".png" if $i eq 4;
			} else {
				if ($elem =~ /night/i) {
					if ($i eq 0) {
						if ($slot0[1] >= 10) {
							if ((((($tempp <= 32) and $temp_convert) or (($tempp <=0) and !$temp_convert)) and $temp_convert) or (($tempp <=0) and !$temp_convert))  {
								if ($slot0[1] <= 30) {
									$slot0[3] = "images/conditions/night_flurries.png";
									$slot0[4] = "Flurries";
								} else {
									$slot0[3] = "images/conditions/night_snow.png";
									$slot0[4] = "Snow";	
								}
							} else {
								$slot0[3] = "images/conditions/night_rain.png";
								$slot0[4] = "Showers";
							}
						} else {
							$slot0[3] = "images/conditions/night.png";
							$slot0[4] = "Clear";
						}
					} elsif ($i eq 1) {
						if ($slot1[1] >= 10) {
							if ((($tempp <= 32) and $temp_convert) or (($tempp <=0) and !$temp_convert)) {
								if ($slot1[1] <= 30) {
									$slot1[3] = "images/conditions/night_flurries.png";
									$slot1[4] = "Flurries";
								} else {
									$slot1[3] = "images/conditions/night_snow.png";
									$slot1[4] = "Snow";	
								}
							} else {
								$slot1[3] = "images/conditions/night_rain.png";
								$slot1[4] = "Showers";
							}
						} else {
							$slot1[3] = "images/conditions/night.png";
							$slot1[4] = "Clear";
						}	
					} elsif ($i eq 2) {
						if ($slot2[1] >= 10) {
							if ((($tempp <= 32) and $temp_convert) or (($tempp <=0) and !$temp_convert)) {
								if ($slot2[1] <= 30) {
									$slot2[3] = "images/conditions/night_flurries.png";
									$slot2[4] = "Flurries";
								} else {
									$slot2[3] = "images/conditions/night_snow.png";
									$slot2[4] = "Snow";	
								}
							} else {
								$slot2[3] = "images/conditions/night_rain.png";
								$slot2[4] = "Showers";
							}
						} else {
							$slot2[3] = "images/conditions/night.png";
							$slot2[4] = "Clear";
						}
					} elsif ($i eq 3) {
						if ($slot3[1] >= 10) {
							if ((($tempp <= 32) and $temp_convert) or (($tempp <=0) and !$temp_convert)) {
								if ($slot3[1] <= 30) {
									$slot3[3] = "images/conditions/night_flurries.png";
									$slot3[4] = "Flurries";
								} else {
									$slot3[3] = "images/conditions/night_snow.png";
									$slot3[4] = "Snow";	
								}
							} else {
								$slot3[3] = "images/conditions/night_rain.png";
								$slot3[4] = "Showers";
							}
						} else {
							$slot3[3] = "images/conditions/night.png";
							$slot3[4] = "Clear";
						}	
					} elsif ($i eq 4) {
						if ($slot4[1] >= 10) {
							if ((($tempp <= 32) and $temp_convert) or (($tempp <=0) and !$temp_convert)) {
								if ($slot4[1] <= 30) {
									$slot4[3] = "images/conditions/night_flurries.png";
									$slot4[4] = "Flurries";
								} else {
									$slot4[3] = "images/conditions/night_snow.png";
									$slot4[4] = "Snow";	
								}
							} else {
								$slot4[3] = "images/conditions/night_rain.png";
								$slot4[4] = "Showers";
							}
						} else {
							$slot4[3] = "images/conditions/night.png";
							$slot4[4] = "Clear";
						}	
					}			
				} else {
					$slot0[3] = "images/conditions/na.jpg" if $i eq 0;	
					$slot1[3] = "images/conditions/na.jpg" if $i eq 1;
					$slot2[3] = "images/conditions/na.jpg" if $i eq 2;
					$slot3[3] = "images/conditions/na.jpg" if $i eq 3;
					$slot4[3] = "images/conditions/na.jpg" if $i eq 4;
				}
			}
			$i++;
		}
		$slot0[6] = "<img src=\"images/temp_no_change.png\">";
		if ($slot1[1] < $slot0[1]) {
			$slot1[6] = "<img src=\"images/temp_down.png\">";
		} elsif ($slot1[1] > $slot0[1]) {
			$slot1[6] = "<img src=\"images/temp_up.png\">";
		} else {
			$slot1[6] = "<img src=\"images/temp_no_change.png\">";
		}
		if ($slot2[1] < $slot0[1]) {
			$slot2[6] = "<img src=\"images/temp_down.png\">";
		} elsif ($slot2[1] > $slot0[1]) {
			$slot2[6] = "<img src=\"images/temp_up.png\">";
		} else {
			$slot2[6] = "<img src=\"images/temp_no_change.png\">";
		}
		if ($slot3[1] < $slot1[1]) {
			$slot3[6] = "<img src=\"images/temp_down.png\">";
		} elsif ($slot3[1] > $slot1[1]) {
			$slot3[6] = "<img src=\"images/temp_up.png\">";
		} else {
			$slot3[6] = "<img src=\"images/temp_no_change.png\">";
		}
		if ($slot4[1] < $slot2[1]) {
			$slot4[6] = "<img src=\"images/temp_down.png\">";
		} elsif ($slot4[1] > $slot2[1]) {
			$slot4[6] = "<img src=\"images/temp_up.png\">";
		} else {
			$slot4[6] = "<img src=\"images/temp_no_change.png\">";
		}
		my $slot_temp = $slot0[2];
		$slot_temp =~ s/(High|Low)//i;
		my $slot_tempp = $output{"temperature_v"};
		if ($slot_temp < $slot_tempp) {
			$slot0[5] = "<img src=\"images/temp_down.png\">";
		} elsif ($slot_temp > $slot_tempp) {
			$slot0[5] = "<img src=\"images/temp_up.png\">";
		} else {
			$slot0[5] = "<img src=\"images/temp_no_change.png\">";
		}
		my $slot_temp = $slot1[2];
		$slot_temp =~ s/(High|Low)//i;
		my $slot_tempp = $output{"temperature_v"};
		if ($slot_temp < $slot_tempp) {
			$slot1[5] = "<img src=\"images/temp_down.png\">";
		} elsif ($slot_temp > $slot_tempp) {
			$slot1[5] = "<img src=\"images/temp_up.png\">";
		} else {
			$slot1[5] = "<img src=\"images/temp_no_change.png\">";
		}
		my $slot_temp = $slot2[2];
		$slot_temp =~ s/(High|Low)//i;
		my $slot_tempp = $slot0[2];
		$slot_tempp =~ s/(High|Low)//i;
		if ($slot_temp < $slot_tempp) {
			$slot2[5] = "<img src=\"images/temp_down.png\">";
		} elsif ($slot_temp > $slot_tempp) {
			$slot2[5] = "<img src=\"images/temp_up.png\">";
		} else {
			$slot2[5] = "<img src=\"images/temp_no_change.png\">";
		}
		my $slot_temp = $slot3[2];
		$slot_temp =~ s/(High|Low)//i;
		my $slot_tempp = $slot1[2];
		$slot_tempp =~ s/(High|Low)//i;
		if ($slot_temp < $slot_tempp) {
			$slot3[5] = "<img src=\"images/temp_down.png\">";
		} elsif ($slot_temp > $slot_tempp) {
			$slot3[5] = "<img src=\"images/temp_up.png\">";
		} else {
			$slot3[5] = "<img src=\"images/temp_no_change.png\">";
		}
		my $slot_temp = $slot4[2];
		$slot_temp =~ s/(High|Low)//i;
		my $slot_tempp = $slot2[2];
		$slot_tempp =~ s/(High|Low)//i;
		if ($slot_temp < $slot_tempp) {
			$slot4[5] = "<img src=\"images/temp_down.png\">";
		} elsif ($slot_temp > $slot_tempp) {
			$slot4[5] = "<img src=\"images/temp_up.png\">";
		} else {
			$slot4[5] = "<img src=\"images/temp_no_change.png\">";
		}
		$slot4[4] = "Unknown" if !$slot4[4];
		return ($issued,
			$slot0[0], $slot1[0], $slot2[0], $slot3[0], $slot4[0],
			$slot0[1], $slot1[1], $slot2[1], $slot3[1], $slot4[1],
			$slot0[2], $slot1[2], $slot2[2], $slot3[2], $slot4[2],
			$slot0[3], $slot1[3], $slot2[3], $slot3[3], $slot4[3],
			$slot0[4], $slot1[4], $slot2[4], $slot3[4], $slot4[4],
			$slot0[5], $slot1[5], $slot2[5], $slot3[5], $slot4[5],
			$slot0[6], $slot1[6], $slot2[6], $slot3[6], $slot4[6]
		);
	}
}

sub main_folders {		
	# Prepare composite information.
	my ($jc_icon, $jc_obj);
	my $composite_speed = param('composite_speed');
	$composite_speed = 150 if !$composite_speed;
	print "\n<table cellspacing=\"0\" cellpadding=\"0\">";
	if ($composite_ani) {
		$jc_icon = "stop.png";
		$jc_obj = "$base_loc?composite_ani=0";
		print "<script language=\"javascript\">\n";
		my $s = $utc_h + 1;
		my $w = 0;
		while ($w <= 23) {
			if ($s >= 24) {
				$s = 0;
			}
			print "\tvar img$w = new Image()\;\n\timg$w.src = \"nexrad/us_composite_" . $s . ".png\"\;\n";
			$s++;
			$w++;
		}
		print <<"		EOF";
			var i = 0;
			var nbImg = $w;
			function animate() {
				document.images[0].src = eval("img" + i ).src;
				i++;
				if (i == nbImg) i=0;
				foo = setTimeout("animate();", $composite_speed);
			}
			</script>
		EOF
	} else {
		$jc_icon = "go.png";
		$jc_obj = "$base_loc?composite_ani=1";	
	}
	print <<"	EOF";
					<tr>
						<td>
							<table cellspacing="0" cellpadding="0">
								<tr>
	EOF
	if ($folder_redir eq "nexrad_locations") {
		print <<"		EOF";
			<td class="subfolder_top" align="left" height="17" width="172">
				<a style="color:#FFFFFF;" href="$base_loc?composite_ani=0">NEXRAD Composite</a>
			</td>
			<td class="folder_top" align="left" height="19" width="172">
				<a style="color:#FFFFFF;" href="$base_loc?folder_redir=nexrad_locations">NEXRAD Locations</a>
			</td>
			<td class="subfolder_top" align="left" height="19" width="172">
				<a style="color:#FFFFFF;" href="$base_loc?folder_redir=international">International</a>
			</td>
		EOF
	} elsif ($folder_redir eq "international") {
		print <<"		EOF";
			<td class="subfolder_top" align="left" height="17" width="172">
				<a style="color:#FFFFFF;" href="$base_loc?composite_ani=0">NEXRAD Composite</a>
			</td>
			<td class="subfolder_top" align="left" height="19" width="172">
				<a style="color:#FFFFFF;" href="$base_loc?folder_redir=nexrad_locations">NEXRAD Locations</a>
			</td>
			<td class="folder_top" align="left" height="19" width="172">
				<a style="color:#FFFFFF;" href="$base_loc?folder_redir=international">International</a>
			</td>
		EOF
	} else {
		print <<"		EOF";
			<td class="folder_top" align="left" height="19" width="172">
				<a style="color:#FFFFFF;" href="$base_loc?composite_ani=0">NEXRAD Composite</a>
			</td>
			<td class="subfolder_top" align="left" height="17" width="172">
				<a style="color:#FFFFFF;" href="$base_loc?folder_redir=nexrad_locations">NEXRAD Locations</a>
			</td>
			<td class="subfolder_top" align="left" height="19" width="172">
				<a style="color:#FFFFFF;" href="$base_loc?folder_redir=international">International</a>
			</td>
		EOF
	}
	print <<"	EOF";
								</tr>
							</table>
						</td>
					</tr>
					<tr>
						<td class="folder" width="645">
							<table>
								<tr>
	EOF
	if($folder_redir eq "nexrad_locations") {
		print <<"		EOF";
			<td>
				<map name="nexrad_locations">
					<area href="http://www.noaa.gov" shape="circle" coords="38, 38, 34">
					<area shape=poly coords="105, 89, 132, 104, 148, 77, 126, 66, 111, 73, 105, 89" href="$base_loc?ui=katx&nexrad=DS.p19r0" alt="Seattle/Tacoma">
					<area shape=poly coords="165, 81, 177, 90, 171, 105, 161, 114, 133, 102, 148, 77, 165, 81" href="$base_loc?ui=kotx&nexrad=DS.p19r0" alt="Spokane">
					<area shape=poly coords="95, 106, 106, 89, 132, 104, 128, 128, 122, 131, 99, 125, 95, 106" href="$base_loc?ui=krtx&nexrad=DS.p19r0" alt="Portland">
					<area shape=poly coords="88, 137, 108, 162, 137, 153, 131, 133, 127, 128, 122, 131, 98, 125, 88, 137" href="$base_loc?ui=kmax&nexrad=DS.p19r0" alt="Medford">
					<area shape=poly coords="130, 134, 128, 127, 132, 102, 160, 113, 165, 126, 153, 133, 130, 134" href="$base_loc?ui=kpdt&nexrad=DS.p19r0" alt="Pendelton">
					<area shape=poly coords="171, 155, 165, 163, 137, 152, 131, 133, 151, 133, 166, 126, 175, 138, 172, 148, 171, 155" href="$base_loc?ui=kcbx&nexrad=DS.p19r0" alt="Boise">
					<area shape=poly coords="190, 111, 188, 92, 177, 90, 171, 105, 160, 115, 165, 126, 175, 138, 196, 128, 190, 111" href="$base_loc?ui=kmsx&nexrad=DS.p19r0" alt="Missoula">
					<area shape=poly coords="214, 98, 212, 117, 196, 128, 190, 111, 188, 92, 204, 89, 214, 98" href="$base_loc?ui=ktfx&nexrad=DS.p19r0" alt="Great Falls">
					<area shape=poly coords="214, 95, 218, 88, 231, 85, 252, 89, 251, 106, 245, 126, 213, 112, 214, 95" href="$base_loc?ui=kggw&nexrad=DS.p19r0" alt="Glasgow">
					<area shape=poly coords="252, 88, 263, 86, 280, 86, 284, 97, 281, 108, 270, 110, 251, 109, 252, 88" href="$base_loc?ui=kmbx&nexrad=DS.p19r0" alt="Minot AFB">
					<area shape=poly coords="285, 113, 284, 121, 274, 128, 249, 128, 245, 125, 250, 109, 269, 110, 281, 108, 285, 113" href="$base_loc?ui=kbis&nexrad=DS.p19r0" alt="Bismark">
					<area shape=poly coords="283, 92, 289, 87, 312, 89, 313, 120, 285, 118, 285, 114, 281, 109, 283, 98, 283, 92" href="$base_loc?ui=kmvx&nexrad=DS.p19r0" alt="Grand Forks">
					<area shape=poly coords="338, 88, 312, 88, 313, 118, 327, 121, 345, 117, 346, 103, 338, 88" href="$base_loc?ui=kdlh&nexrad=DS.p19r0" alt="Duluth">
					<area shape=poly coords="297, 138, 305, 119, 286, 118, 282, 121, 274, 128, 275, 150, 297, 138" href="$base_loc?ui=kabr&nexrad=DS.p19r0" alt="Aberdeen">
					<area shape=poly coords="237, 148, 242, 125, 250, 128, 274, 128, 275, 151, 251, 160, 237, 148" href="$base_loc?ui=kudx&nexrad=DS.p19r0" alt="Rapid City">
					<area shape=poly coords="218, 141, 197, 127, 212, 116, 213, 112, 242, 124, 237, 148, 218, 141" href="$base_loc?ui=kblx&nexrad=DS.p19r0" alt="Billings">
					<area shape=poly coords="82, 138, 71, 155, 75, 173, 93, 173, 108, 162, 87, 136, 82, 138" href="$base_loc?ui=kbhx&nexrad=DS.p19r0" alt="Eureka">
					<area shape=poly coords="97, 180, 114, 181, 124, 157, 107, 163, 91, 174, 97, 180" href="$base_loc?ui=kbbx&nexrad=DS.p19r0" alt="Beale AFB">
					<area shape=poly coords="119, 190, 113, 181, 96, 180, 91, 173, 76, 173, 79, 186, 95, 185, 106, 191, 111, 200, 124, 199, 119, 190" href="$base_loc?ui=kdax&nexrad=DS.p19r0" alt="Sacramento">
					<area shape=poly coords="80, 186, 94, 185, 107, 192, 110, 199, 101, 213, 81, 214, 80, 186" href="$base_loc?ui=kmux&nexrad=DS.p19r0" alt="San Francisco Bay Area">
					<area shape=poly coords="132, 210, 117, 228, 109, 225, 101, 213, 110, 200, 125, 199, 132, 210" href="$base_loc?ui=khnx&nexrad=DS.p19r0" alt="San Joaquin Valley">
					<area shape=poly coords="82, 237, 77, 224, 82, 214, 101, 213, 109, 225, 107, 231, 91, 247, 82, 237" href="$base_loc?ui=kvbx&nexrad=DS.p19r0" alt="Vandenberg AFB">
					<area shape=poly coords="105, 257, 124, 235, 120, 231, 116, 228, 110, 225, 106, 233, 92, 246, 105, 257" href="$base_loc?ui=kvtx&nexrad=DS.p19r0" alt="Los Angeles">
					<area shape=poly coords="124, 236, 135, 237, 134, 246, 124, 248, 106, 256, 124, 236" href="$base_loc?ui=ksox&nexrad=DS.p19r0" alt="Santa Ana Mountains">
					<area shape=poly coords="133, 209, 144, 230, 133, 237, 125, 236, 116, 227, 133, 209" href="$base_loc?ui=keyx&nexrad=DS.p19r0" alt="Edwards AFB">
					<area shape=poly coords="138, 175, 146, 199, 132, 210, 119, 190, 114, 182, 124, 157, 137, 152, 138, 175" href="$base_loc?ui=krgx&nexrad=DS.p19r0" alt="Reno">
					<area shape=poly coords="167, 171, 166, 188, 145, 199, 138, 173, 137, 152, 166, 163, 167, 171" href="$base_loc?ui=klrx&nexrad=DS.p19r0" alt="Elko">
					<area shape=poly coords="155, 194, 164, 213, 172, 229, 165, 241, 151, 244, 135, 243, 135, 236, 144, 230, 133, 209, 146, 198, 155, 194" href="$base_loc?ui=kesx&nexrad=DS.p19r0" alt="Las Vegas">
					<area shape=poly coords="135, 246, 137, 260, 129, 276, 105, 257, 124, 248, 135, 246" href="$base_loc?ui=knkx&nexrad=DS.p19r0" alt="San Diego">
					<area shape=poly coords="152, 244, 165, 259, 168, 280, 149, 287, 129, 276, 137, 260, 135, 243, 152, 244" href="$base_loc?ui=kyux&nexrad=DS.p19r0" alt="Yuma">
					<area shape=poly coords="171, 230, 175, 242, 192, 256, 188, 265, 166, 269, 166, 261, 151, 244, 163, 241, 171, 230" href="$base_loc?ui=kiwa&nexrad=DS.p19r0" alt="Phoenix">
					<area shape=poly coords="192, 257, 208, 256, 212, 281, 201, 297, 177, 296, 168, 280, 167, 269, 188, 265, 192, 257" href="$base_loc?ui=kemx&nexrad=DS.p19r0" alt="Tucson">
					<area shape=poly coords="198, 218, 209, 223, 207, 256, 192, 256, 174, 242, 172, 231, 198, 218" href="$base_loc?ui=kfsx&nexrad=DS.p19r0" alt="Flagstaff">
					<area shape=poly coords="196, 219, 173, 231, 155, 194, 165, 189, 194, 191, 196, 219" href="$base_loc?ui=kicx&nexrad=DS.p19r0" alt="Cedar City">
					<area shape=poly coords="208, 174, 194, 191, 166, 189, 167, 172, 166, 162, 171, 156, 184, 162, 208, 173, 208, 174" href="$base_loc?ui=kmtx&nexrad=DS.p19r0" alt="Salt Lake City">
					<area shape=poly coords="200, 153, 195, 167, 171, 156, 171, 148, 176, 137, 198, 127, 211, 136, 200, 153" href="$base_loc?ui=ksfx&nexrad=DS.p19r0" alt="Pocatello/Idaho Falls">
					<area shape=poly coords="226, 170, 207, 173, 195, 167, 201, 152, 211, 137, 218, 141, 237, 148, 242, 153, 226, 170" href="$base_loc?ui=kriw&nexrad=DS.p19r0" alt="Riverton">
					<area shape=poly coords="229, 215, 210, 223, 196, 217, 194, 191, 209, 173, 226, 170, 234, 197, 229, 215" href="$base_loc?ui=kgjx&nexrad=DS.p19r0" alt="Grand Junction">
					<area shape=poly coords="261, 170, 265, 176, 246, 184, 229, 183, 226, 170, 242, 153, 251, 160, 261, 156, 261, 170" href="$base_loc?ui=kcys&nexrad=DS.p19r0" alt="Cheyenne">
					<area shape=poly coords="257, 195, 247, 197, 234, 197, 230, 183, 245, 184, 256, 179, 257, 195" href="$base_loc?ui=kftg&nexrad=DS.p19r0" alt="Denver/Boulder">
					<area shape=poly coords="265, 208, 253, 222, 232, 220, 229, 215, 234, 196, 248, 197, 257, 194, 265, 208" href="$base_loc?ui=kpux&nexrad=DS.p19r0" alt="Pueblo">
					<area shape=poly coords="241, 242, 237, 254, 207, 256, 209, 224, 229, 215, 232, 220, 246, 222, 241, 242" href="$base_loc?ui=kabx&nexrad=DS.p19r0" alt="Albuquerque">
					<area shape=poly coords="286, 144, 295, 165, 284, 176, 265, 176, 261, 169, 261, 157, 275, 150, 286, 144" href="$base_loc?ui=klnx&nexrad=DS.p19r0" alt="North Platte">
					<area shape=poly coords="286, 198, 265, 208, 256, 191, 256, 180, 265, 176, 279, 176, 286, 198" href="$base_loc?ui=kgld&nexrad=DS.p19r0" alt="Goodland">
					<area shape=poly coords="297, 210, 291, 223, 277, 224, 258, 216, 264, 207, 293, 196, 297, 210" href="$base_loc?ui=kddc&nexrad=DS.p19r0" alt="Dodge City">
					<area shape=poly coords="288, 237, 284, 245, 272, 247, 262, 241, 244, 228, 245, 222, 254, 222, 258, 216, 277, 224, 286, 222, 288, 237" href="$base_loc?ui=kama&nexrad=DS.p19r0" alt="Amarillo">
					<area shape=poly coords="266, 244, 262, 256, 247, 269, 237, 255, 241, 241, 244, 228, 266, 244" href="$base_loc?ui=kfdx&nexrad=DS.p19r0" alt="Cannon AFB">
					<area shape=poly coords="210, 268, 208, 255, 237, 254, 247, 269, 228, 268, 210, 268" href="$base_loc?ui=khdx&nexrad=DS.p19r0" alt="Holloman AFB">
					<area shape=poly coords="245, 299, 206, 289, 212, 279, 210, 268, 228, 268, 247, 269, 252, 287, 245, 299" href="$base_loc?ui=kepz&nexrad=DS.p19r0" alt="El Paso">
					<area shape=poly coords="286, 261, 280, 269, 268, 270, 253, 263, 262, 256, 266, 243, 273, 247, 281, 245, 286, 261" href="$base_loc?ui=klbb&nexrad=DS.p19r0" alt="Lubbock">
					<area shape=poly coords="278, 280, 262, 314, 245, 300, 252, 287, 247, 268, 253, 263, 268, 270, 276, 269, 278, 280" href="$base_loc?ui=kmaf&nexrad=DS.p19r0" alt="Midland/Odessa">
					<area shape=poly coords="300, 291, 302, 279, 285, 263, 276, 270, 278, 280, 271, 294, 300, 291" href="$base_loc?ui=ksjt&nexrad=DS.p19r0" alt="San Angelo">
					<area shape=poly coords="296, 292, 305, 314, 297, 330, 262, 312, 271, 294, 296, 292" href="$base_loc?ui=kdfx&nexrad=DS.p19r0" alt="Laughlin AFB">
					<area shape=poly coords="301, 338, 304, 358, 309, 364, 339, 364, 349, 346, 345, 330, 301, 338" href="$base_loc?ui=kbro&nexrad=DS.p19r0" alt="Brownsville">
					<area shape=poly coords="344, 330, 301, 338, 297, 330, 305, 314, 328, 309, 346, 321, 344, 330" href="$base_loc?ui=kcrp&nexrad=DS.p19r0" alt="Corpus Christi">
					<area shape=poly coords="328, 309, 305, 314, 296, 292, 300, 289, 315, 291, 328, 296, 328, 309" href="$base_loc?ui=kewx&nexrad=DS.p19r0" alt="Austin/San Antonio">
					<area shape=poly coords="334, 287, 328, 296, 315, 291, 300, 289, 302, 279, 321, 275, 338, 274, 334, 287" href="$base_loc?ui=kgrk&nexrad=DS.p19r0" alt="Central Texas">
					<area shape=poly coords="310, 277, 302, 279, 285, 264, 286, 261, 284, 254, 307, 253, 310, 277" href="$base_loc?ui=kdyx&nexrad=DS.p19r0" alt="Dyess AFB">
					<area shape=poly coords="299, 232, 306, 240, 307, 253, 284, 254, 281, 245, 288, 237, 288, 232, 299, 232" href="$base_loc?ui=kfdr&nexrad=DS.p19r0" alt="Frederick">
					<area shape=poly coords="296, 215, 305, 216, 312, 220, 312, 226, 304, 227, 299, 232, 288, 232, 286, 223, 292, 222, 296, 215" href="$base_loc?ui=kvnx&nexrad=DS.p19r0" alt="Vance AFB">
					<area shape=poly coords="313, 225, 320, 231, 325, 246, 307, 253, 306, 241, 299, 231, 304, 227, 313, 225" href="$base_loc?ui=ktlx&nexrad=DS.p19r0" alt="Oklahoma City">
					<area shape=poly coords="325, 246, 333, 246, 336, 274, 321, 275, 310, 277, 307, 252, 325, 246" href="$base_loc?ui=kfws&nexrad=DS.p19r0" alt="Dallas/Fort Worth">
					<area shape=poly coords="322, 235, 334, 221, 326, 206, 313, 222, 314, 227, 321, 231, 322, 235" href="$base_loc?ui=kinx&nexrad=DS.p19r0" alt="Tulsa">
					<area shape=poly coords="303, 194, 313, 200, 326, 206, 315, 221, 306, 216, 295, 215, 297, 210, 293, 195, 303, 194" href="$base_loc?ui=kict&nexrad=DS.p19r0" alt="Wichita">
					<area shape=poly coords="295, 165, 305, 178, 304, 194, 293, 196, 286, 198, 279, 176, 284, 176, 295, 165" href="$base_loc?ui=kuex&nexrad=DS.p19r0" alt="Hastings">
					<area shape=poly coords="305, 179, 321, 175, 324, 205, 312, 200, 304, 194, 305, 179" href="$base_loc?ui=ktwx&nexrad=DS.p19r0" alt="Topeka">
					<area shape=poly coords="295, 163, 317, 152, 321, 175, 305, 179, 299, 170, 295, 163" href="$base_loc?ui=koax&nexrad=DS.p19r0" alt="Omaha">
					<area shape=poly coords="309, 121, 318, 152, 294, 163, 286, 143, 297, 139, 305, 120, 309, 121" href="$base_loc?ui=kfsd&nexrad=DS.p19r0" alt="Sioux Falls">
					<area shape=poly coords="338, 119, 337, 131, 332, 146, 318, 151, 309, 120, 314, 118, 327, 121, 338, 119" href="$base_loc?ui=kmpx&nexrad=DS.p19r0" alt="Minneapolis">
					<area shape=poly coords="338, 87, 359, 81, 380, 91, 375, 111, 362, 114, 346, 115, 345, 102, 338, 87" href="$base_loc?ui=kmqt&nexrad=DS.p19r0" alt="Marquette">
					<area shape=poly coords="380, 94, 393, 95, 406, 108, 397, 120, 384, 124, 374, 112, 380, 94" href="$base_loc?ui=kapx&nexrad=DS.p19r0" alt="Gaylord">
					<area shape=poly coords="380, 119, 372, 129, 364, 132, 351, 128, 342, 116, 347, 115, 363, 114, 375, 111, 380, 119" href="$base_loc?ui=kgrb&nexrad=DS.p19r0" alt="Green Bay">
					<area shape=poly coords="359, 131, 356, 138, 349, 147, 332, 147, 337, 131, 338, 119, 342, 116, 351, 128, 359, 131" href="$base_loc?ui=karx&nexrad=DS.p19r0" alt="La Crosse">
					<area shape=poly coords="341, 148, 346, 174, 321, 175, 317, 152, 331, 146, 341, 148" href="$base_loc?ui=kdmx&nexrad=DS.p19r0" alt="Des Moines">
					<area shape=poly coords="355, 140, 363, 152, 360, 165, 346, 174, 341, 147, 349, 147, 355, 140" href="$base_loc?ui=kdvn&nexrad=DS.p19r0" alt="Quad Cities">
					<area shape=poly coords="376, 136, 376, 142, 363, 151, 355, 140, 359, 131, 363, 131, 371, 129, 376, 136" href="$base_loc?ui=kmkx&nexrad=DS.p19r0" alt="Milwaukee">
					<area shape=poly coords="392, 122, 394, 132, 392, 137, 388, 140, 376, 137, 372, 129, 379, 119, 384, 122, 392, 122" href="$base_loc?ui=kgrr&nexrad=DS.p19r0" alt="Grand Rapids/Muskegon">
					<area shape=poly coords="406, 109, 418, 118, 411, 135, 404, 141, 393, 135, 393, 131, 392, 121, 398, 118, 406, 109" href="$base_loc?ui=kdtx&nexrad=DS.p19r0" alt="Detroit">
					<area shape=poly coords="381, 160, 360, 160, 363, 150, 375, 143, 376, 137, 385, 139, 381, 160" href="$base_loc?ui=klot&nexrad=DS.p19r0" alt="Chicago">
					<area shape=poly coords="346, 195, 324, 203, 321, 175, 338, 174, 346, 195" href="$base_loc?ui=keax&nexrad=DS.p19r0" alt="Kansas City/Pleasant Hill">
					<area shape=poly coords="372, 185, 364, 206, 350, 202, 345, 194, 338, 174, 347, 174, 354, 168, 372, 185" href="$base_loc?ui=klsx&nexrad=DS.p19r0" alt="St. Louis">
					<area shape=poly coords="348, 217, 334, 222, 325, 203, 345, 195, 350, 202, 362, 206, 348, 217" href="$base_loc?ui=ksgf&nexrad=DS.p19r0" alt="Springfield">
					<area shape=poly coords="384, 179, 372, 185, 355, 169, 360, 165, 362, 160, 380, 160, 382, 171, 384, 179" href="$base_loc?ui=kilx&nexrad=DS.p19r0" alt="Central Illinois">
					<area shape=poly coords="390, 189, 391, 199, 387, 211, 363, 206, 372, 185, 382, 180, 390, 189" href="$base_loc?ui=kpah&nexrad=DS.p19r0" alt="Paducah">
					<area shape=poly coords="347, 218, 345, 243, 325, 246, 322, 235, 333, 222, 347, 218" href="$base_loc?ui=ksrx&nexrad=DS.p19r0" alt="Western Arkansas/Fort Smith">
					<area shape=poly coords="362, 221, 368, 237, 361, 250, 350, 250, 345, 243, 347, 218, 360, 207, 364, 206, 362, 221" href="$base_loc?ui=klzk&nexrad=DS.p19r0" alt="Little Rock">
					<area shape=poly coords="386, 212, 392, 216, 385, 230, 378, 241, 368, 238, 362, 219, 364, 206, 386, 211, 386, 212" href="$base_loc?ui=knqa&nexrad=DS.p19r0" alt="Memphis">
					<area shape=poly coords="363, 258, 354, 269, 346, 276, 336, 274, 333, 245, 345, 244, 350, 249, 359, 250, 363, 258" href="$base_loc?ui=kshv&nexrad=DS.p19r0" alt="Shreveport">
					<area shape=poly coords="350, 290, 347, 275, 338, 275, 334, 287, 328, 296, 328, 308, 346, 321, 365, 311, 350, 290" href="$base_loc?ui=khgx&nexrad=DS.p19r0" alt="Houston/Galveston">
					<area shape=poly coords="374, 282, 380, 300, 364, 310, 350, 289, 348, 282, 374, 282" href="$base_loc?ui=klch&nexrad=DS.p19r0" alt="Lake Charles">
					<area shape=poly coords="375, 268, 373, 282, 348, 282, 347, 275, 354, 268, 363, 257, 375, 268" href="$base_loc?ui=kpoe&nexrad=DS.p19r0" alt="Fort Polk">
					<area shape=poly coords="381, 237, 400, 249, 388, 266, 375, 268, 363, 258, 359, 251, 361, 250, 368, 238, 377, 241, 381, 237" href="$base_loc?ui=kjan&nexrad=DS.p19r0" alt="Jackson">
					<area shape=poly coords="401, 274, 412, 292, 380, 299, 373, 281, 375, 267, 388, 266, 392, 260, 401, 274" href="$base_loc?ui=klix&nexrad=DS.p19r0" alt="New Orleans/Baton Rouge">
					<area shape=rect coords="465, 22, 507, 58" href="$base_loc?ui=kcbw&nexrad=DS.p19r0" alt="Caribou">
					<area shape=poly coords="476, 59, 472, 74, 474, 84, 466, 87, 455, 84, 443, 71, 464, 58, 476, 59" href="$base_loc?ui=kcxx&nexrad=DS.p19r0" alt="Burlington">
					<area shape=poly coords="506, 75, 488, 84, 474, 82, 471, 73, 476, 58, 506, 58, 506, 75" href="$base_loc?ui=kgyx&nexrad=DS.p19r0" alt="Portland">
					<area shape=poly coords="462, 87, 460, 98, 453, 104, 445, 107, 427, 94, 444, 72, 454, 83, 462, 87" href="$base_loc?ui=ktyx&nexrad=DS.p19r0" alt="Montague">
					<area shape=poly coords="512, 90, 508, 107, 489, 102, 481, 96, 481, 84, 487, 84, 506, 75, 512, 90" href="$base_loc?ui=kbox&nexrad=DS.p19r0" alt="Boston">
					<area shape=poly coords="485, 99, 476, 105, 471, 108, 464, 105, 459, 99, 462, 88, 466, 88, 475, 82, 482, 85, 481, 96, 485, 99" href="$base_loc?ui=kenx&nexrad=DS.p19r0" alt="Albany">
					<area shape=poly coords="446, 108, 446, 116, 440, 123, 435, 129, 428, 126, 418, 119, 427, 94, 446, 108" href="$base_loc?ui=kbuf&nexrad=DS.p19r0" alt="Buffalo">
					<area shape=poly coords="468, 108, 469, 117, 460, 119, 452, 119, 446, 116, 447, 107, 453, 104, 459, 100, 464, 104, 468, 108" href="$base_loc?ui=kbgm&nexrad=DS.p19r0" alt="Binghamton">
					<area shape=poly coords="501, 126, 481, 118, 469, 116, 470, 108, 476, 105, 485, 99, 490, 102, 507, 107, 501, 126" href="$base_loc?ui=kokx&nexrad=DS.p19r0" alt="Upton">
					<area shape=poly coords="408, 150, 402, 156, 381, 158, 385, 137, 392, 139, 395, 135, 403, 140, 408, 150" href="$base_loc?ui=kiwx&nexrad=DS.p19r0" alt="Northern Indiana">
					<area shape=poly coords="434, 129, 429, 136, 420, 152, 407, 149, 402, 142, 410, 135, 418, 119, 427, 125, 434, 129" href="$base_loc?ui=kcle&nexrad=DS.p19r0" alt="Cleveland">
					<area shape=poly coords="498, 136, 479, 132, 461, 132, 460, 119, 470, 115, 480, 118, 500, 125, 499, 135, 498, 136" href="$base_loc?ui=kdix&nexrad=DS.p19r0" alt="Philadelphia">
					<area shape=poly coords="461, 129, 458, 138, 450, 142, 442, 137, 435, 129, 440, 122, 446, 116, 453, 119, 460, 119, 461, 129" href="$base_loc?ui=kccx&nexrad=DS.p19r0" alt="State College">
					<area shape=poly coords="447, 141, 450, 154, 436, 158, 420, 152, 430, 136, 435, 129, 442, 137, 447, 141" href="$base_loc?ui=kpbz&nexrad=DS.p19r0" alt="Pittsburgh">
					<area shape=poly coords="407, 169, 397, 176, 384, 179, 382, 172, 380, 160, 382, 159, 401, 155, 407, 169" href="$base_loc?ui=kind&nexrad=DS.p19r0" alt="Indianapolis">
					<area shape=poly coords="428, 155, 423, 165, 417, 170, 407, 169, 401, 155, 408, 149, 421, 152, 428, 155" href="$base_loc?ui=kiln&nexrad=DS.p19r0" alt="Wilmington">
					<area shape=poly coords="405, 171, 415, 181, 413, 192, 404, 191, 395, 189, 390, 189, 382, 180, 397, 176, 405, 171" href="$base_loc?ui=klvx&nexrad=DS.p19r0" alt="Louisville">
					<area shape=poly coords="404, 192, 400, 199, 389, 213, 387, 212, 391, 198, 390, 189, 395, 189, 404, 192" href="$base_loc?ui=khpx&nexrad=DS.p19r0" alt="Fort Campbell">
					<area shape=poly coords="421, 168, 429, 174, 432, 180, 428, 185, 422, 186, 415, 181, 406, 172, 408, 170, 417, 170, 421, 168" href="$base_loc?ui=kjkl&nexrad=DS.p19r0" alt="Jackson">
					<area shape=poly coords="496, 136, 494, 149, 478, 148, 472, 144, 465, 139, 458, 138, 461, 132, 479, 132, 496, 136" href="$base_loc?ui=kdox&nexrad=DS.p19r0" alt="Dover AFB">
					<area shape=poly coords="481, 148, 473, 155, 458, 160, 450, 154, 448, 143, 459, 138, 465, 139, 473, 145, 481, 148" href="$base_loc?ui=klwx&nexrad=DS.p19r0" alt="Sterling">
					<area shape=poly coords="450, 155, 440, 180, 432, 179, 429, 173, 421, 167, 429, 154, 436, 158, 450, 155" href="$base_loc?ui=krlx&nexrad=DS.p19r0" alt="Charleston">
					<area shape=poly coords="500, 167, 486, 173, 475, 171, 465, 168, 458, 160, 474, 155, 482, 148, 494, 149, 500, 167" href="$base_loc?ui=kakq&nexrad=DS.p19r0" alt="Wakefield">
					<area shape=poly coords="468, 169, 461, 181, 455, 189, 447, 188, 443, 182, 441, 178, 450, 154, 468, 169" href="$base_loc?ui=kfcx&nexrad=DS.p19r0" alt="Blacksburg">
					<area shape=poly coords="503, 167, 512, 184, 504, 201, 485, 192, 480, 189, 481, 183, 481, 173, 487, 172, 503, 167" href="$base_loc?ui=kmhx&nexrad=DS.p19r0" alt="Morehead City">
					<area shape=poly coords="480, 189, 465, 195, 455, 189, 468, 170, 476, 171, 481, 173, 481, 183, 480, 189" href="$base_loc?ui=krax&nexrad=DS.p19r0" alt="Raleigh/Durham">
					<area shape=poly coords="449, 189, 436, 198, 424, 202, 412, 191, 416, 182, 422, 187, 428, 185, 433, 179, 441, 180, 449, 189" href="$base_loc?ui=kmrx&nexrad=DS.p19r0" alt="Knoxville/Tri Cities">
					<area shape=poly coords="392, 215, 389, 213, 401, 199, 404, 192, 413, 192, 425, 202, 392, 215" href="$base_loc?ui=kohx&nexrad=DS.p19r0" alt="Nashville">
					<area shape=poly coords="490, 220, 473, 211, 467, 204, 464, 195, 479, 189, 485, 192, 505, 201, 490, 220" href="$base_loc?ui=kltx&nexrad=DS.p19r0" alt="Wilmington">
					<area shape=poly coords="452, 190, 449, 204, 447, 215, 435, 215, 426, 210, 424, 202, 435, 198, 448, 189, 452, 190" href="$base_loc?ui=kgsp&nexrad=DS.p19r0" alt="Greer">
					<area shape=poly coords="463, 216, 453, 221, 446, 214, 450, 205, 452, 190, 454, 189, 465, 195, 467, 205, 473, 208, 463, 216" href="$base_loc?ui=kcae&nexrad=DS.p19r0" alt="Columbia">
					<area shape=poly coords="428, 212, 420, 224, 411, 228, 401, 224, 392, 214, 424, 202, 428, 212" href="$base_loc?ui=khtx&nexrad=DS.p19r0" alt="Northern Alabama">
					<area shape=poly coords="439, 228, 435, 236, 430, 236, 421, 231, 419, 226, 429, 211, 435, 216, 441, 215, 439, 228" href="$base_loc?ui=kffc&nexrad=DS.p19r0" alt="Atlanta">
					<area shape=poly coords="489, 221, 488, 233, 469, 237, 459, 229, 456, 220, 473, 209, 489, 221" href="$base_loc?ui=kclx&nexrad=DS.p19r0" alt="Charleston">
					<area shape=poly coords="463, 234, 457, 237, 449, 241, 438, 240, 435, 236, 439, 227, 441, 214, 447, 214, 457, 223, 456, 224, 459, 229, 463, 234" href="$base_loc?ui=kjgx&nexrad=DS.p19r0" alt="Robins AFB">
					<area shape=poly coords="406, 227, 403, 238, 399, 250, 381, 237, 392, 215, 401, 224, 406, 227" href="$base_loc?ui=kgwx&nexrad=DS.p19r0" alt="Columbus AFB">
					<area shape=poly coords="422, 228, 418, 239, 411, 252, 399, 250, 406, 226, 412, 228, 419, 225, 422, 228" href="$base_loc?ui=kbmx&nexrad=DS.p19r0" alt="Birmingham">
					<area shape=poly coords="431, 237, 427, 244, 411, 252, 422, 230, 427, 236, 431, 237" href="$base_loc?ui=kmxx&nexrad=DS.p19r0" alt="East Alabama">
					<area shape=poly coords="485, 234, 495, 246, 479, 259, 471, 264, 460, 253, 462, 248, 458, 238, 464, 233, 468, 237, 485, 234" href="$base_loc?ui=kjax&nexrad=DS.p19r0" alt="Jacksonville">
					<area shape=poly coords="460, 250, 456, 256, 449, 252, 441, 248, 441, 240, 448, 241, 457, 237, 462, 247, 460, 250" href="$base_loc?ui=kvax&nexrad=DS.p19r0" alt="Moody AFB">
					<area shape=poly coords="443, 248, 436, 252, 428, 255, 415, 257, 412, 252, 427, 244, 431, 237, 435, 237, 439, 240, 441, 242, 443, 248" href="$base_loc?ui=keox&nexrad=DS.p19r0" alt="Fort Rucker">
					<area shape=poly coords="421, 288, 412, 292, 392, 259, 400, 249, 412, 252, 418, 257, 421, 288" href="$base_loc?ui=kmob&nexrad=DS.p19r0" alt="Mobile">
					<area shape=poly coords="433, 253, 440, 263, 448, 283, 421, 288, 418, 257, 433, 253" href="$base_loc?ui=kevx&nexrad=DS.p19r0" alt="Northwest Florida">
					<area shape=poly coords="465, 258, 447, 282, 440, 262, 433, 252, 442, 248, 454, 255, 460, 255, 465, 258" href="$base_loc?ui=ktlh&nexrad=DS.p19r0" alt="Tallahassee">
					<area shape=poly coords="496, 247, 510, 258, 515, 273, 497, 282, 481, 275, 471, 264, 496, 247" href="$base_loc?ui=kmlb&nexrad=DS.p19r0" alt="Melbourne">
					<area shape=poly coords="494, 282, 484, 295, 471, 306, 447, 281, 465, 259, 481, 275, 494, 282" href="$base_loc?ui=ktbw&nexrad=DS.p19r0" alt="Tampa Bay Area">
					<area shape=poly coords="528, 288, 522, 314, 501, 304, 485, 294, 495, 281, 516, 272, 528, 288" href="$base_loc?ui=kamx&nexrad=DS.p19r0" alt="Miami">
					<area shape=poly coords="507, 337, 484, 336, 471, 322, 472, 304, 486, 294, 501, 304, 523, 314, 507, 337" href="$base_loc?ui=kbyx&nexrad=DS.p19r0" alt="Key West">
				</map>
				<img border="0" src="nexrad/us_composite.png" usemap="#nexrad_locations"><br>
			</td>
		EOF
	} elsif ($folder_redir eq "international") {
		build_countries();
	} else {
		print <<"		EOF";
			<td>
				<map name="composite_map">
					<area href="http://www.noaa.gov" shape="circle" coords="38, 38, 34">
					<area href="$base_loc?ui=AK" shape="polygon" coords="23, 307, 31, 292, 49, 283, 74, 290, 77, 317, 84, 321, 92, 338, 88, 345, 84, 343, 80, 335, 75, 329, 67, 325, 60, 332, 55, 337, 50, 337, 39, 343, 33, 346, 29, 345, 30, 338, 23, 331, 20, 325, 20, 318" alt="Alaska">
					<area href="$base_loc?ui=AL" shape="polygon" coords="396, 222, 417, 215, 434, 237, 434, 245, 437, 253, 416, 262, 420, 267, 411, 270, 409, 270, 407, 265, 400, 245" alt="Alabama">
					<area href="$base_loc?ui=AZ" shape="polygon" coords="167, 216, 211, 221, 204, 283, 188, 282, 154, 263, 155, 259, 156, 254, 161, 241, 161, 235, 162, 231" alt="Airizona">
					<area href="$base_loc?ui=AR" shape="polygon" coords="336, 219, 373, 211, 373, 215, 378, 212, 376, 227, 375, 234, 373, 240, 373, 245, 373, 249, 350, 255, 348, 251, 344, 249, 342, 248, 342, 238" alt="Arkansas">
					<area href="$base_loc?ui=CA" shape="polygon" coords="99, 144, 131, 153, 123, 181, 162, 239, 157, 252, 156, 258, 153, 260, 133, 259, 131, 252, 127, 244, 121, 237, 115, 233, 106, 230, 99, 201, 100, 197, 100, 188, 95, 178, 94, 168, 94, 161" alt="California">
					<area href="$base_loc?ui=CO" shape="polygon" coords="214, 180, 268, 178, 270, 219, 264, 222, 210, 220" alt="Colorado">
					<area href="$base_loc?ui=CT" shape="polygon" coords="477, 103, 488, 96, 492, 101, 482, 109" alt="Connecticut">
					<area href="$base_loc?ui=DE" shape="polygon" coords="478, 135, 486, 142, 484, 143" alt="Delaware">
					<area href="$base_loc?ui=FL" shape="polygon" coords="415, 263, 439, 255, 445, 257, 466, 250, 470, 250, 470, 246, 474, 246, 504, 280, 509, 298, 506, 301, 500, 304, 499, 300, 499, 298, 496, 297, 493, 297, 475, 282, 472, 275, 469, 268, 454, 263, 441, 270, 430, 266, 415, 269" alt="Florida">
					<area href="$base_loc?ui=GA" shape="polygon" coords="418, 215, 438, 209, 471, 227, 472, 245, 468, 246, 468, 249, 444, 255, 440, 255" alt="Georgia">
					<area href="$base_loc?ui=HI" shape="polygon" coords="104, 299, 114, 294, 120, 297, 160, 309, 164, 316, 172, 322, 172, 330, 159, 337, 154, 336, 154, 331, 152, 325, 151, 320, 147, 317, 130, 311, 126, 306, 121, 304, 115, 305, 110, 306" alt="Hawaii">
					<area href="$base_loc?ui=ID" shape="polygon" coords="152, 159, 197, 166, 202, 140, 190, 140, 184, 126, 181, 126, 183, 117, 174, 103, 175, 92, 169, 90, 161, 119, 165, 123, 156, 134, 159, 136" alt="Idaho">
					<area href="$base_loc?ui=IL" shape="polygon" coords="354, 150, 374, 145, 380, 150, 389, 179, 388, 186, 388, 190, 387, 194, 387, 196, 386, 199, 383, 199, 380, 201, 374, 196, 371, 193, 370, 192, 370, 188, 367, 185, 364, 185, 361, 183, 357, 179, 355, 175, 356, 171, 357, 167" alt="Illinois">
					<area href="$base_loc?ui=IN" shape="polygon" coords="379, 151, 388, 179, 388, 188, 388, 189, 397, 188, 403, 184, 407, 177, 411, 172, 400, 144" alt="Indiana">
					<area href="$base_loc?ui=IA" shape="polygon" coords="308, 148, 346, 141, 352, 147, 357, 150, 359, 155, 357, 159, 355, 165, 355, 170, 321, 177, 309, 156" alt="Iowa">
					<area href="$base_loc?ui=KS" shape="polygon" coords="269, 189, 324, 181, 327, 186, 331, 190, 334, 213, 271, 220" alt="Kansas">
					<area href="$base_loc?ui=KY" shape="polygon" coords="388, 192, 386, 198, 382, 200, 382, 203, 381, 207, 381, 209, 434, 189, 437, 184, 440, 180, 435, 176, 432, 172, 429, 169, 422, 169, 417, 171, 413, 171, 411, 172, 407, 176, 403, 182, 401, 185, 398, 186, 395, 188, 391, 189, 391, 187" alt="Kentucky">
					<area href="$base_loc?ui=LA" shape="polygon" coords="348, 257, 375, 250, 378, 256, 378, 259, 377, 265, 376, 270, 378, 273, 394, 269, 396, 275, 396, 277, 405, 287, 401, 288, 393, 292, 388, 292, 381, 290, 377, 289, 369, 292, 358, 292, 359, 282, 359, 278, 356, 272" alt="Louisiana">
					<area href="$base_loc?ui=ME" shape="polygon" coords="474, 68, 489, 80, 493, 70, 497, 62, 501, 55, 500, 50, 496, 48, 487, 38, 482, 35, 477, 38, 473, 38, 473, 45, 476, 54, 476, 60" alt="Maine">
					<area href="$base_loc?ui=MD" shape="polygon" coords="445, 150, 471, 135, 472, 139, 483, 145, 477, 146, 472, 148, 467, 145, 459, 145, 448, 151" alt="Maryland">
					<area href="$base_loc?ui=MA" shape="polygon" coords="475, 96, 490, 87, 496, 90, 500, 88, 501, 93, 497, 94, 492, 93, 479, 101" alt="Massachusetts">
					<area href="$base_loc?ui=MI" shape="polygon" coords="387, 148, 410, 139, 412, 126, 405, 116, 399, 122, 398, 118, 399, 108, 393, 104, 387, 98, 378, 96, 364, 97, 359, 98, 350, 105, 350, 109, 356, 111, 365, 113, 369, 113, 382, 105, 387, 107, 384, 111, 379, 118, 381, 128, 385, 134, 386, 141" alt="Michigan">
					<area href="$base_loc?ui=MN" shape="polygon" coords="295, 95, 304, 122, 302, 127, 306, 129, 310, 149, 347, 141, 344, 135, 337, 131, 336, 127, 333, 124, 332, 119, 333, 113, 338, 107, 343, 100, 350, 94, 340, 93, 316, 91, 313, 87, 307, 89, 303, 93, 298, 93" alt="Minnesota">
					<area href="$base_loc?ui=MS" shape="polygon" coords="376, 228, 395, 223, 407, 271, 398, 274, 395, 269, 377, 273, 378, 266, 379, 258, 375, 252, 375, 249, 375, 240, 375, 233" alt="Mississippi">
					<area href="$base_loc?ui=MO" shape="polygon" coords="320, 178, 354, 172, 356, 179, 360, 183, 364, 186, 367, 187, 367, 190, 369, 194, 375, 198, 379, 202, 382, 204, 381, 209, 380, 213, 374, 214, 374, 212, 337, 219, 335, 209, 332, 196, 330, 188, 326, 183" alt="Missouri">
					<area href="$base_loc?ui=MT" shape="polygon" coords="173, 91, 251, 98, 251, 138, 203, 134, 201, 138, 191, 138, 186, 131, 184, 128, 181, 127, 181, 120, 181, 117, 178, 112, 174, 103, 173, 97" alt="Montana">
					<area href="$base_loc?ui=NE" shape="polygon" coords="252, 158, 309, 156, 320, 176, 322, 181, 320, 183, 271, 188, 269, 179, 253, 179" alt="Nebraska">
					<area href="$base_loc?ui=NV" shape="polygon" coords="130, 154, 122, 183, 162, 236, 162, 225, 164, 222, 167, 219, 176, 164" alt="Nevada">
					<area href="$base_loc?ui=NH" shape="polygon" coords="473, 69, 479, 92, 489, 87, 489, 83, 476, 67" alt="New Hampshire">
					<area href="$base_loc?ui=NJ" shape="polygon" coords="471, 114, 479, 114, 483, 119, 485, 130, 485, 135, 477, 133, 477, 126, 474, 122, 472, 118" alt="New Jersey">
					<area href="$base_loc?ui=NM" shape="polygon" coords="210, 222, 262, 223, 262, 226, 264, 277, 231, 278, 227, 279, 217, 279, 215, 284, 206, 283" alt="New Mexico">
					<area href="$base_loc?ui=NY" shape="polygon" coords="481, 110, 463, 78, 455, 80, 451, 86, 449, 94, 451, 100, 437, 108, 434, 112, 434, 119, 431, 124, 431, 128, 467, 110, 474, 115, 479, 115, 485, 118, 491, 107, 487, 107, 486, 113" alt="New York">
					<area href="$base_loc?ui=NC" shape="polygon" coords="426, 210, 441, 190, 444, 186, 445, 185, 485, 170, 495, 168, 495, 179, 495, 187, 493, 192, 489, 199, 486, 202, 470, 195, 464, 197, 462, 199, 457, 196, 447, 201, 440, 207" alt="North Carolina">
					<area href="$base_loc?ui=ND" shape="polygon" coords="251, 98, 296, 94, 306, 123, 253, 127" alt="North Dakota">
					<area href="$base_loc?ui=OH" shape="polygon" coords="401, 143, 412, 139, 418, 140, 425, 133, 430, 129, 439, 148, 437, 153, 433, 159, 430, 167, 427, 168, 419, 170, 414, 170, 411, 170" alt="Ohio">
					<area href="$base_loc?ui=OK" shape="polygon" coords="262, 222, 335, 214, 342, 249, 335, 245, 330, 250, 325, 251, 316, 251, 308, 251, 302, 251, 296, 249, 293, 248, 290, 226, 262, 227" alt="Oklahoma">
					<area href="$base_loc?ui=OR" shape="polygon" coords="99, 144, 153, 158, 159, 145, 158, 130, 162, 126, 163, 120, 155, 117, 140, 117, 131, 115, 125, 113, 121, 107, 117, 104, 98, 140" alt="Oregon">
					<area href="$base_loc?ui=PA" shape="polygon" coords="429, 129, 467, 110, 471, 114, 473, 120, 476, 125, 478, 130, 440, 148" alt="Pennsylvania">
					<area href="$base_loc?ui=RI" shape="polygon" coords="493, 102, 489, 98, 492, 96, 496, 99" alt="Rhode Island">
					<area href="$base_loc?ui=SC" shape="polygon" coords="438, 208, 444, 213, 471, 229, 476, 223, 482, 211, 483, 205, 479, 199, 471, 194, 463, 197, 458, 197, 454, 197, 439, 204" alt="South Carolina">
					<area href="$base_loc?ui=SD" shape="polygon" coords="252, 129, 303, 124, 307, 129, 309, 157, 299, 156, 290, 156, 253, 159" alt="South Dakota">
					<area href="$base_loc?ui=TN" shape="polygon" coords="380, 209, 444, 185, 443, 191, 428, 211, 376, 226, 380, 215, 376, 214" alt="Tennesee">
					<area href="$base_loc?ui=TX" shape="polygon" coords="230, 278, 263, 277, 262, 227, 290, 227, 291, 243, 293, 247, 304, 250, 313, 251, 321, 251, 331, 253, 337, 252, 342, 251, 346, 253, 354, 272, 356, 278, 359, 289, 359, 292, 335, 311, 328, 314, 325, 321, 326, 329, 327, 335, 330, 341, 324, 343, 310, 341, 288, 307, 282, 301, 272, 302, 268, 306, 265, 313, 258, 312, 254, 308, 248, 299, 243, 289, 238, 284" alt="Texas">
					<area href="$base_loc?ui=UT" shape="polygon" coords="175, 164, 167, 215, 210, 221, 213, 178, 198, 176, 199, 166" alt="Utah">
					<area href="$base_loc?ui=VT" shape="polygon" coords="459, 79, 473, 69, 479, 92, 475, 94" alt="Vermont">
					<area href="$base_loc?ui=VA" shape="polygon" coords="432, 191, 488, 165, 478, 152, 470, 149, 467, 146, 459, 146, 457, 154, 453, 160, 448, 172, 444, 177, 436, 179" alt="Virginia">
					<area href="$base_loc?ui=WA" shape="polygon" coords="117, 83, 128, 86, 130, 80, 167, 89, 161, 118, 149, 116, 139, 116, 132, 115, 124, 113, 121, 110, 119, 105, 115, 104" alt="Washington">
					<area href="$base_loc?ui=WV" shape="polygon" coords="429, 170, 436, 176, 443, 177, 449, 175, 453, 164, 453, 160, 457, 150, 455, 146, 449, 149, 445, 149, 440, 150, 437, 150, 437, 156, 435, 159, 429, 163" alt="West Virginia">
					<area href="$base_loc?ui=WI" shape="polygon" coords="355, 150, 375, 143, 373, 118, 369, 120, 369, 114, 361, 110, 350, 106, 343, 106, 334, 111, 332, 118, 332, 125, 334, 131, 338, 133, 344, 136, 349, 143" alt="Wisconsin">
					<area href="$base_loc?ui=WY" shape="polygon" coords="202, 137, 252, 137, 251, 178, 199, 176" alt="Wyoming">
				</map>
				<img border="0" src="nexrad/us_composite.png" usemap="#composite_map"><br>
			</td>
			<td valign="bottom" align="right">
				<a href="$jc_obj"><img src="images/$jc_icon" width="17" height="17" border="0" alt="Animate"></a>
			</td>
		EOF
	}
	print <<"	EOF";

								</tr>
								<br>
							</table>
						</td>
					</tr>
				</table>
	EOF
	print "<script language=\"javascript\">animate()\;</script>" if $composite_ani;
}

sub unindent {
	# Remove extra indents.
	local $_ = shift;
	my ($indent) = sort /^([ \t]*)\S/gm;
	s/^$indent//gm;
	return $_;
}

sub disem_header {
	print <<"	EOF";
		<!-- header //-->
		<table>
			<tr>
				<td class="pagetop_icon" width="63">
				</td>
				<td>
					<table alight="left" valign="bottom" width="255">
						<tr class="pagetop">
							Open Weather
						</tr>
						<tr class="pagetop_desc">
							The open source weather alternative!
						</tr>
						<tr>
							<td class="small">
								<form action="$base_loc">
									Search: 
									<input type="text" name="ui" maxlength="255" style="width: 50px;" class="header">
									<input type="image" src="images/go.png" align="absmiddle" width="18" height="17" style="border: none;" alt="Query">
									(e.g. $home_zip, $home_state, or $home_icao)
								</form>
							</td>
						</tr>
					</table>
				</td>
			</tr>
		</table>
		<!-- header //-->
		<br>
	EOF
		
}

sub metric_footer {
	print <<"	EOF";
		<br> 
		<a style="color:#FFFFFF;" href="$base_loc?ui=$ui\&metric=0"><img src="images/flags/f0-us.gif" border="0"></a>
		<a style="color:#FFFFFF;" href="$base_loc?ui=$ui\&metric=1"><img src="images/flags/f0-eu.gif" border="0"></a>
	EOF
}

sub disem_footer {
	metric_footer() if ($ui =~ /([A-Z]){1}([A-Z0-9]){3}/i);
	print <<"	EOF";
		<!-- footer //-->
		<br>
		<table width="100%" valign="center" align="right">
			<tr>
				<td>
					<div style="border-top: 1px solid #2F6690; padding-top: 5px; padding-right: 5px; width=100%">
						<div align="right" class="small">
							If you would like information on Open Weather it can be found <a href="http://weather.riven.net">here</a>.<br>
							Distributed under the GNU <a href="COPYING">General Public License</a>.<br>
							Open Weather $openweather_version ($version) - <a href="http://www.riven.net/~moose">Jade E. Deane</a><br>
							<a href="javascript:history.go(-1)"><img src="images/go_reverse.png" border="0"></a>
							<a href="javascript:history.go(+1)"><img src="images/go.png" border="0"></a>
						</div>
					</div>
				</td>
			</tr>
		</table>
        <!-- footer //-->	
	EOF
}

sub disem {
    # Disseminate information.
	print "Content-type: text/html\n\n";
    print <<"	EOF";
		<html>
		<head>
			<title>Open Weather</title>
			<META HTTP-EQUIV="Pragma" CONTENT="no-cache">
			<META HTTP-EQUIV="Expires" CONTENT="-1">
			<link href="openweather.css" rel="stylesheet" type="text/css">
	EOF
	print <<"	EOF";
		</head>
		<body>
	EOF
	disem_header() if $header;
    if ($error) {
        if ($site_info) {
			print $output{"site_info"} . "<br>\n";
        }
        print "<br><img src=\"images/error.png\">\&nbsp\;\&nbsp\;$error<br>\n";
    } elsif (@geo_output) {
        foreach (@geo_output) {
            print "$_";
        }
	} elsif (@sites_output) {
		foreach (@sites_output) {
			print "$_";	
		}	
    } elsif (($nexrad) and ($nexrad_i)) {
		my $cnum;
		my $nexrad_b = $nexrad;
		$nexrad_b =~ s/DS.//;
		if (($utc_mm >=0) and ($utc_mm <= 9)) { 
			$cnum = 0;
		} elsif (($utc_mm >=10) and ($utc_mm <= 19)) {
			$cnum = 10;
		} elsif (($utc_mm >=20) and ($utc_mm <= 29)) {
			$cnum = 20;
		} elsif (($utc_mm >=30) and ($utc_mm <= 39)) {
			$cnum = 30;
		} elsif (($utc_mm >=40) and ($utc_mm <= 49)) {
			$cnum = 40;
		} elsif (($utc_mm >=50) and ($utc_mm <= 59)) {
			$cnum = 50;
		}
        print $output{"site_info"};
		print <<"		EOF";
			<br>
			<table cellspacing="0" cellpadding="0">
				<tr>
					<td>
						<table cellspacing="0" cellpadding="0">
							<tr>
		EOF
		if ($nexrad eq "DS.p19r0") {
			print <<"			EOF";
									<td class="folder_top" align="left" height="19" width="172">
										<a style="color:#FFFFFF;" href="$base_loc?ui=$ui&nexrad=DS.p19r0">54 nmi 0.5&deg angle</a>
									</td>
									<td class="subfolder_top" align="left" height="17" width="172">
										<a style="color:#FFFFFF;" href="$base_loc?ui=$ui&nexrad=DS.p20-r">248 nmi 4&deg angle</a>
									</td>	
									<td class="subfolder_top" align="left" height="17" width="172">
										<a style="color:#FFFFFF;" href="$base_loc?ui=$ui&nexrad=DS.78ohp">Rainfall Totals (1hr)</a>
									</td>	
			EOF
		} elsif ($nexrad eq "DS.78ohp") {
			print <<"			EOF";
									<td class="subfolder_top" align="left" height="17" width="172">
										<a style="color:#FFFFFF;" href="$base_loc?ui=$ui&nexrad=DS.p19r0">54 nmi 0.5&deg angle</a>
									</td>
									<td class="subfolder_top" align="left" height="17" width="172">
										<a style="color:#FFFFFF;" href="$base_loc?ui=$ui&nexrad=DS.p20-r">248 nmi 4&deg angle</a>
									</td>
									<td class="folder_top" align="left" height="19" width="172">
										<a style="color:#FFFFFF;" href="$base_loc?ui=$ui&nexrad=DS.78ohp">Rainfall Totals (1hr)</a>
									</td>		
			EOF
		} elsif ($nexrad eq "DS.p20-r") {
			print <<"			EOF";
									<td class="subfolder_top" align="left" height="17" width="172">
										<a style="color:#FFFFFF;" href="$base_loc?ui=$ui&nexrad=DS.p19r0">54 nmi 0.5&deg angle</a>
									</td>
									<td class="folder_top" align="left" height="19" width="172">
										<a style="color:#FFFFFF;" href="$base_loc?ui=$ui&nexrad=DS.p20-r">248 nmi 4&deg angle</a>
									</td>
									<td class="subfolder_top" align="left" height="17" width="172">
										<a style="color:#FFFFFF;" href="$base_loc?ui=$ui&nexrad=DS.78ohp">Rainfall Totals (1hr)</a>
									</td>		
			EOF
		}
		print <<"		EOF";
							</tr>
						</table>
					</td>
				</tr>
				<tr>
					<td class="folder" height="620" width="620">
						<table>
							<tr>
								<td>
		EOF
		#<img src="$blobimg?loc=$ui&rtype=$nexrad_b&cnum=$cnum">
		my $start_image = $ui . "_" . $nexrad . "_latest.png";
		nexrad_ani() if $nexrad_ani;
		print <<"		EOF";
									<img src="nexrad/$start_image">
								</td>
								<td valign="bottom" align="right">
									<a href="$base_loc?ui=$ui&nexrad=$nexrad&nexrad_ani=1"><img src="images/go.png" border="0"></a>
								</td>
		EOF
		print "<script language=\"javascript\">animate()\;</script>" if $nexrad_ani;
		print <<"		EOF";
							</tr>
						</table>
					</td>
				</tr>
			</table>
		EOF
    } elsif (!$ui) {
		print <<"		EOF";
			<table cellspacing="0" cellpadding="0">
				<tr>
					<td class="folder_top" height="19" width="172">
						Welcome
					</td>
				</tr>
				<tr>
					<td class="folder" width="645">
						<table>
							<tr>
								<td class="date">
									$output{"date"}
								</td>
							</tr>
							<tr>
								<td class="local_information">
									Open Weather running at <a href="http://$hostname">$hostname</a> located in <a href="$base_loc?ui=$home_icao">$home_icao</a>.
								</td>
							</tr>
							<tr>
								<td>
									Welcome to Open Weather;  The open source collection of weather tools for weather enthusiasts,
									by weather enthusiasts.  If you would like to obtain a copy of the latest distribution or additional 
									information, please visit <a href="http://weather.riven.net">here</a>.
									<br><br>
									Select a location below or enter a query at the top of this page.   
									Please note that while the list of sites reporting weather information is large,
									a site might not be reporting current information.  This varies a great deal station
									to station.<br><br>
									Unless otherwise noted, all times are UTC.  To view radar animation, Javascript is required.<br><br>
								</td>
							</tr>
							<br>
						</table>
					</td>
				</tr>
			</table>
			<br>
		EOF
		main_folders();
		print <<"		EOF";
			</table>
		EOF
    } else {
        print <<"		EOF";
			<table width="100%">
				<tr>
					<td>
						<table>
							<tr>
								<td>
									$output{"site_info"}
								</td>
							</tr>
							<tr>
								<td>
		EOF
		if ($raw_prompt) {
			if ($raw_report) {
				print "<br>Cycle " . $query_cycle . "Z: " . $output{"raw_report"} . "\n"; 
			} else {
				print "<br>Click <a href=\"$base_loc?ui=$ui&raw_report=1\">here</a> to see the raw METAR report.";
			}
		}
		print <<"		EOF";
								</td>
							</tr>
						</table>
						<br><br>
						<table width="100%">
							<tr>
								<td align="left" valign="top">
									<table border="0" cellspacing="1.5" cellpadding="1.5" width="265">
										<tr>
											<td valign="bottom">
												<div style="width: 300px">
													<div align="left">
														<div class="smallheader">
															Current Conditions:
														</div>
													</div>
												</div>
											</td> 
										</tr>
									</table>
									<table border="0" cellspacing="0" cellpadding="0" width="265">
										<tr>
											<td valign="bottom">
												Temperature:
											</td>   
											<td class="big"align="right">
												$temp_dongle <b>$output{"temperature"}</b>
											</td>
										</tr>
									</table>
									<table border="0" cellspacing="0" cellpadding="0" width="265">
										<tr>
											<td>
												$output{"index_desc"}:
											</td>   
											<td align="right">
												$output{"index"}
											</td>
										</tr>
									</table>
									<table border="0" cellspacing="0" cellpadding="0" width="265">
										<tr>
											<td>
												Change:

											</td>   
											<td align="right">
												$output{"temperature_change"}
											</td>
										</tr>
									</table>
									<table border="0" cellspacing="0" cellpadding="0" width="265">
										<tr>
											<td>
												Dew Point:

											</td>   
											<td align="right">
												$output{"dew_point"}
											</td>
										</tr>
									</table>
									<table border="0" cellspacing="0" cellpadding="0" width="265">
										<tr>
											<td>
												Relative Humidity:
											</td>   
											<td align="right">
												$output{"relative_humidity"}
											</td>
										</tr>
									</table>
									<table border="0" cellspacing="0" cellpadding="0" width="265">
										<tr>
											<td>
													Sky:
											</td>   
											<td align="right">
												$output{"sky"}
											</td>
										</tr>
									</table>
									<table border="0" cellspacing="0" cellpadding="0" width="265">
										<tr>
											<td>
												Weather:
											</td>   
											<td align="right">
												$output{"conditions"}
											</td>
										</tr>
									</table>
									<table border="0" cellspacing="0" cellpadding="0" width="265">
										<tr>
											<td>
												Wind:
											</td>   
											<td align="right">
												$output{"wind"}
											</td>
										</tr>
									</table>
									<br>
									<table border="0" cellspacing="0" cellpadding="0" width="265">
										<tr>
											<td class="small">
												$output{"updated"}
											</td>
										</tr>
									</table>
									<br><br>
									<table border="0" cellspacing="2" width="100%">
										<tr>
											<td align="left" valign="top" class="small">
												<img src="images/temp_up.png"> Rising/Higher<br>
												<img src="images/temp_up_sharp.png"> Rising Sharply<br>
												<img src="images/temp_no_change.png"> No Change/Unknown<br>
											</td>
											<td align="left" valign="top" class="small">
												<img src="images/temp_down.png"> Falling/Lower<br>
												<img src="images/temp_down_sharp.png"> Falling Sharply<br>
											</td>
										</tr>
									</table>
								</td>
		EOF
        if ($get_forecast) {
			my ($issued, 
				$slot0_head, $slot1_head, $slot2_head, $slot3_head, $slot4_head,
				$slot0_precip, $slot1_precip, $slot2_precip, $slot3_precip, $slot4_precip,
				$slot0_temp, $slot1_temp, $slot2_temp, $slot3_temp, $slot4_temp,
				$slot0_image, $slot1_image, $slot2_image, $slot3_image, $slot4_image,
				$slot0_desc, $slot1_desc, $slot2_desc, $slot3_desc, $slot4_desc,
				$slot0_dongle, $slot1_dongle, $slot2_dongle, $slot3_dongle, $slot4_dongle,
				$slot0_pdongle, $slot1_pdongle, $slot2_pdongle, $slot3_pdongle, $slot4_pdongle
			) = forecast();
			print <<"			EOF";
				<td align="left" valign="top">
					<table border="0" cellspacing="1.5" cellpadding="1.5" width="235">
						<tr>
							<div style="width: 300px">
								<div align="left">
									<div class="smallheader">
										Extended Forecast:
									</div>
								</div>
							</div>
						</tr>
			EOF
			if ($issued) {
				print <<"				EOF";
						<tr>
							<td valign="bottom">
                                    <table border="0" cellpadding="2" cellspacing="0">
                                            <tr>
                                                    <td align="right"><img src="images/forecast_precip.png" height="17" width="17"
														ALT="Chance of precipitation">
													</td>
                                            </tr>
											<tr>
													<td align="right"><img src="images/forecast_temp.png" height="17" width="17"
														ALT="Temperature">
													</td>
											</tr>
                                    </table>
                            </td>
							<td valign="bottom">
								<div style="border-right: 1px solid #000000; border-bottom: 1px solid #000000; padding-top: 0px; padding-right: 0px; width=100%">
								<table border="0" cellpadding="2" cellspacing="0" width="86">
									<tr>
										<td align="center" class="forecastheader">$slot0_head</td>
									</tr>
									<tr>
										<td align="center" class="forecast"><img src="$slot0_image" alt="$slot0_desc" width="48" height="48" border="0"></td>
									</tr>
									<tr>
										<td align="center" class="forecast_small">$slot0_desc</td>
									</tr>
									<tr>
										<td align="center" class="forecast_small">$slot0_precip% $slot0_pdongle</td>
									</tr>
									<tr>
										<td align="center" class="forecast_small">
											
												$slot0_dongle $slot0_temp$temp_noti
											
										</td>
									</tr>
								</table>
								</div>
							</td>
							<td valign="bottom">
								<div style="border-right: 1px solid #000000; border-bottom: 1px solid #000000; padding-top: 0px; padding-right: 0px; width=100%">
								<table border="0" cellpadding="2" cellspacing="0" width="86">
									<tr>
										<td align="center" class="forecastheader">$slot1_head</td>
									</tr>
									<tr>
										<td align="center" class="forecast"><img src="$slot1_image" alt="$slot1_desc" width="48" height="48" border="0" ></td>
									</tr>
									<tr>
										<td align="center" class="forecast_small">$slot1_desc</td>
									</tr>
									<tr>
										<td align="center" class="forecast_small">$slot1_precip% $slot1_pdongle</td>
									</tr>
									<tr>
										<td align="center" class="forecast_small">
											
												$slot1_dongle $slot1_temp$temp_noti
											
										</td>
									</tr>
								</table>
								</div>
							</td>
							<td valign="bottom">
								<div style="border-right: 1px solid #000000; border-bottom: 1px solid #000000; padding-top: 0px; padding-right: 0px; width=100%">
								<table border="0" cellpadding="2" cellspacing="0" width="86">
									<tr>
										<td align="center" class="forecastheader">$slot2_head</td>
									</tr>
									<tr>
										<td align="center" class="forecast"><img src="$slot2_image" alt="$slot2_desc "width="48" height="48" border="0"></td>
									</tr>
									<tr>
										<td align="center" class="forecast_small">$slot2_desc</td>
									</tr>
									<tr>
										<td align="center" class="forecast_small">$slot2_precip% $slot2_pdongle</td>
									</tr>
									<tr>
										<td align="center" class="forecast_small">
											
												$slot2_dongle $slot2_temp$temp_noti
											
										</td>
									</tr>
								</table>
								</div>
							</td>
							<td valign="bottom">
								<div style="border-right: 1px solid #000000; border-bottom: 1px solid #000000; padding-top: 0px; padding-right: 0px; width=100%">
								<table border="0" cellpadding="2" cellspacing="0" width="86">
									<tr>
										<td align="center" class="forecastheader">$slot3_head</td>
									</tr>
									<tr>
										<td align="center" class="forecast"><img src="$slot3_image" alt="$slot3_desc" width="48" height="48" border="0"></td>
									</tr>
									<tr>
										<td align="center" class="forecast_small">$slot3_desc</td>
									</tr>
									<tr>
										<td align="center" class="forecast_small">$slot3_precip% $slot3_pdongle</td>
									</tr>
									<tr>
										<td align="center" class="forecast_small">
											
												$slot3_dongle $slot3_temp$temp_noti
											
										</td>
									</tr>
								</table>
								</div>
							</td>
							<td valign="bottom">
								<div style="border-right: 1px solid #000000; border-bottom: 1px solid #000000; padding-top: 0px; padding-right: 0px; width=100%">
								<table border="0" cellpadding="2" cellspacing="0" width="86">
									<tr>
										<td align="center" class="forecastheader">$slot4_head</td>
									</tr>
									<tr>
										<td align="center" class="forecast"><img src="$slot4_image" alt="$slot4_desc" width="48" height="48" border="0"></td>
									</tr>
									<tr>
										<td align="center" class="forecast_small">$slot4_desc</td>
									</tr>
									<tr>
										<td align="center" class="forecast_small">$slot4_precip% $slot4_pdongle</td>
									</tr>
									<tr>
										<td align="center" class="forecast_small">
											
												$slot4_dongle $slot4_temp$temp_noti
											
										</td>
									</tr>
								</table>
								</div>
							</td>
						</tr>
				EOF
			} else {
				print <<"				EOF";
					<br>
					There is no current forecast for this site.
				EOF
			}
			print <<"			EOF";			
					</table>
					<br>
				</td>
			EOF
        }
		print <<"		EOF";
				</tr>
			</table>
			<br>
		EOF
		if ($mrtg and $ui =~ /($mrtg_sites)/i) {
			my $mrtg_site = lc($ui);
			print <<"			EOF";
			<table>
				<tr>
					<td align="left">
						<div style="width: 300px">
							<div align="left">
								<div class="smallheader">
									Graph:
								</div>
							</div>
						</div>
						<a href="graphs/$mrtg_site.html"><img src="graphs/$mrtg_site-day.png" border="0"></a>
					</td>
				</tr>
			</table>
			EOF
		}
		print <<"		EOF";
			<br>
			$output{"nexrad"}
			<br>
		EOF
    }
	disem_footer() if $footer;
    print <<"	EOF";
		</body>
		</html>
	EOF
	exit;
}

sub main {
	if ($metric) {	
		$temp_convert = 0;
	} else {
		$temp_convert = 1;
	}
	if ($temp_convert) {
		$temp_noti = "\&deg\;F";
	} else {
		$temp_noti = "\&deg\;C";
	}
    $query_cycle = param('cycle');
    $nexrad = param('nexrad');
	$output{"date"} = "$utc_day, $utc_month $utc_d, $utc_y";
    disem() if !$ui;
	db_establish();
	countries();
	if ($ui =~ /($countries){1}/) {
		sites();
	} elsif ($ui =~ /[0-9]{5}/) {
        $range = 30 unless $range;
        geo($ui, $range);
    } elsif ($ui =~ /([A-Z]){1}([A-Z0-9]){3}/i) {
		$ui = uc($ui);
        if (!$query_cycle) {
            $query_cycle = get_cycle($utc_c) unless $query_cycle;
        }
        site();
	} elsif ((length($ui) eq 2) and ($ui =~ /$state_names_pat/i)) {
		$ui = uc($ui);
		geo($ui);
	} elsif ($folder_redir) {
		disem();
    } else {
        $error = "Sorry, entry not a vaild US Zip Code, state abbreviation, or ICAO site identifier!<br>\n";
        disem();
	}
    $dbh->disconnect() or db_error;
}

&main();