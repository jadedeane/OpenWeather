#!/usr/bin/env perl
# Open Weather 0.22
# Script: openweather_nexrad.pl rev 34
# Developer: Jade E. Deane (jade.deane@gmail.com)
# Purpose: Fetch NEXRAD information.

use strict;

use DBI;
use LWP::UserAgent;
use POSIX qw(strftime);
use Image::Magick;

# Config.
my %openweather;
my $Configfile = "";
open (CONF,$Configfile) or die "Could not open config file $Configfile: $! \n";
my $code = join ('', <CONF>);
close (CONF);
eval $code;

# Global items.
my $dbh;
my $blob;
my $noaa_server = $openweather{"noaa_server"};
my $nexrad = $openweather{"nexrad"};
my $images = $openweather{"images"};
my $enable_nexrad = $openweather{"enable_nexrad"};
my $select_sites = $openweather{"select_sites"};
my $db_type = $openweather{'db_type'};
my $db_username = $openweather{'db_username'};
my $db_password = $openweather{'db_password'};
my $db_hostname = $openweather{'db_hostname'};
my $db_database = $openweather{'db_database'};
my $utc_c = strftime "%H%M", gmtime;
my $utc_h = int(strftime "%H", gmtime);
my $utc_mm = int(strftime "%M", gmtime);
my $utc_y = int(strftime "%Y", gmtime);
my $utc_m = int(strftime "%m", gmtime); 
my $utc_month = strftime "%B", gmtime;
my $utc_d = int(strftime "%d", gmtime); 
my $utc_day = strftime "%A", gmtime;
my $utc_e = int(strftime "%e", gmtime);
my $date_text = (strftime "%Y", gmtime) 
	. "-" . (strftime "%m", gmtime) 
	. "-" . (strftime "%d", gmtime) 
	. " " . (strftime "%H", gmtime) 
	. ":" . (strftime "%M", gmtime);

sub db_error {
    print "$DBI::errstr\n";
}
        
sub db_establish {
    my %DBConnectOpts = ( PrintError => 0, RaiseError => 0 );
    my $DSN = "DBI:$db_type:$db_database:$db_hostname";
    $dbh = DBI->connect($DSN, $db_username, $db_password, \%DBConnectOpts) or db_error();
}

sub blob_to_db {
	my $f = shift;
	my $tof = 0;
	my ($base_loc, $rtype, $cnum, $sqlb, $sth);
	if ($f =~ /(\w\w\w\w)_\w+\.(.....)_latest_(\d+)\.png/ ) {
	   $base_loc = $1;
	   $rtype = $2;
	   $cnum = $3;
	   $tof = 1;
	}
	if ($f =~ /us_composite_(\d+)\.png/) {
		$base_loc = 'US';
		$rtype = 'composite';
		$cnum = $1;
		$tof = 1;
	}
	if ($tof) {
		$dbh->do("DELETE FROM radimg WHERE loc='$base_loc' AND rtype='$rtype' AND cnum='$cnum'");
    	$sqlb =  "INSERT INTO radimg VALUES ('$base_loc', '$rtype', $cnum, now(), ?)";
		$sth = $dbh->prepare($sqlb) or die "Prepare fails for stmt\nError = ", DBI::errstr;
		$sth->bind_param(1, $blob, DBI::SQL_BINARY);  # Critical
		unless ($sth->execute) {
			print"\n\tExecute fails for stmt:\nError = ", DBI::errstr;
			$sth->finish;
			$dbh->disconnect;
			die "\n\t\tClean up finished\n";
		}
	  $sth->finish;
	}
}

sub hi_composite {
	my $c_ua = new LWP::UserAgent;
	my $c_d = "$nexrad/hi_composite.gif";
	my $c_url = "http://$noaa_server/pub/SL.us008001/DF.gif/DC.radar/DS.p19r0/AR.hawaii/latest.gif";
	my $c_request = new HTTP::Request('GET', $c_url);
	my $c_response = $c_ua->request($c_request, $c_d);
	my $filler= Image::Magick->new();
	$filler->Read("$images/filler.gif");
	my $image = Image::Magick->new();
	$image->Read($c_d);
	$image->Crop(geometry=>'620x500+55+95');
	$image->Transparent(color=>"#FFFFFF");
	$image->Transparent(color=>"#000000");
	$image->Transparent(color=>"#CECECE");
	#$image->Opaque(color=>'#000000',fill=>'#103049');
	$image->Opaque(color=>'#0000C8',fill=>'#019501');
	$image->Opaque(color=>'#00FFFF',fill=>'#51C000');
	$image->Opaque(color=>'#0000FF',fill=>'#1B841B');
	$image->Composite(image=>$filler,compose=>'over',x=>0,y=>332);
	$image->Resize(width=>96,height=>66,blur=>0);
	$image->Write(filename=>$c_d);
	print "hi_composite done\n";
}

sub ak_composite {
	my $c_ua = new LWP::UserAgent;
	my $c_d = "$nexrad/ak_composite.gif";
	my $c_url = "http://$noaa_server/pub/SL.us008001/DF.gif/DC.radar/DS.p19r0/AR.alaska/latest.gif";
	my $c_request = new HTTP::Request('GET', $c_url);
	my $c_response = $c_ua->request($c_request, $c_d);
	my $filler= Image::Magick->new();
	$filler->Read("$images/filler.gif");
	my $image = Image::Magick->new();
	$image->Read($c_d);
	$image->Crop(geometry=>'620x500+55+95');
	$image->Transparent(color=>"#FFFFFF");
	$image->Transparent(color=>"#000000");
	$image->Transparent(color=>"#CECECE");
	#$image->Opaque(color=>'#000000',fill=>'#103049');
	$image->Opaque(color=>'#0000C8',fill=>'#019501');
	$image->Opaque(color=>'#00FFFF',fill=>'#51C000');
	$image->Opaque(color=>'#0000FF',fill=>'#1B841B');
	$image->Composite(image=>$filler,compose=>'over',x=>0,y=>332);
	$image->Resize(width=>96,height=>66,blur=>0);
	$image->Write(filename=>$c_d);
	print "ak_composite done\n";
}

sub us_composite {
	hi_composite();
	ak_composite();
	my $c_ua = new LWP::UserAgent;
	my $c_d = "$nexrad/us_composite.png";
	my $c_anid = "$nexrad/us_composite_" . $utc_h . ".png";
	#my $filler = Image::Magick->new();
	my $legend = Image::Magick->new();
	my $noaa = Image::Magick->new();
	my $hawaii = Image::Magick->new();
	my $hawaii_nexrad = Image::Magick->new();
	my $alaska = Image::Magick->new();
	my $alaska_nexrad = Image::Magick->new();
	#$filler->Read("$images/filler.gif");
	$legend->Read("$images/legend.gif");
	$noaa->Read("$images/noaa.gif");
	$hawaii->Read("$images/hawaii.png");
	$hawaii_nexrad->Read("$nexrad/hi_composite.gif");
	$alaska->Read("$images/alaska.png");
	$alaska_nexrad->Read("$nexrad/ak_composite.gif");
	my $c_url = "http://$noaa_server/pub/SL.us008001/DF.gif/DC.radar/DS.74rcm/AR.conus/latest.gif";
	my $c_request = new HTTP::Request('GET', $c_url);
	my $c_response = $c_ua->request($c_request, $c_d);
	#if ((length $c_response) <= 0) {
	#	print "FUCK\n";
	#	exit;
	#}
	my $image = Image::Magick->new(magick=>'PNG');
	$image->Read($c_d);
	$image->Crop(geometry=>'620x500+1+75');
	$image->Transparent(color=>"#CECECE");
	$image->Transparent(color=>"#FFFFFF");
	#$image->Opaque(color=>'#5B5F71',fill=>'#F6FF00');
	$image->Opaque(color=>'#000000',fill=>'#103049');
	$image->Opaque(color=>'#0000C8',fill=>'#019501');
	$image->Opaque(color=>'#00FFFF',fill=>'#51C000');  
	#$image->Composite(image=>$filler,compose=>'over',x=>0,y=>290);
	$image->Composite(image=>$legend,compose=>'over',x=>5,y=>280);
	$image->Composite(image=>$noaa,compose=>'over',x=>5,y=>5);
	$image->Composite(image=>$hawaii,compose=>'over',x=>95,y=>285);
	$image->Composite(image=>$hawaii_nexrad,compose=>'over',x=>97,y=>291);
	$image->Composite(image=>$alaska,compose=>'over',x=>10,y=>285);
	$image->Composite(image=>$alaska_nexrad,compose=>'over',x=>5,y=>291);
	$image->Annotate(font=>'arial.ttf',pointsize=>10,stroke=>'#000000',text=>$date_text,x=>485,y=>420);
	$image->Write(filename=>$c_d); 
	$image->Write(filename=>$c_anid);
	$blob = $image->ImageToBlob();
	&blob_to_db($c_anid);
	print "us_composite done\n";
	exit;
}

sub site {
	my $radtype = shift;
	my $sql;
	my $noaa_path = "pub/SL.us008001/DF.gif/DC.radar/" . $radtype;
	if ($ARGV[1]) {
		$sql = "SELECT icao,place,state,country FROM si WHERE country='United States' AND icao='$ARGV[1]'";
	} else {
		$sql = "SELECT icao,place,state,country FROM si WHERE country='United States' " . $select_sites . " AND place LIKE '%nexrad%' ORDER BY state,place";
	}
    my $sth = $dbh->prepare ($sql);
    $sth->execute() || db_error();
    my $ua = new LWP::UserAgent;
    while (my @row = $sth->fetchrow_array) {
        my $icao_lc = lc $row[0];
        my $gg = "SI.$icao_lc/latest.gif";
        my $d_gif = "$nexrad/$row[0]"."_" . $radtype . "_latest_$utc_mm.gif";
		my $d_png = "$nexrad/$row[0]"."_" . $radtype . "_latest_$utc_mm.png";
		my $latest_png = "$nexrad/$row[0]"."_" . $radtype . "_latest.png";
        my $url = "http://$noaa_server/$noaa_path/$gg";
        print "Fetching $url ";
        my $request = new HTTP::Request('GET', $url);
        if (my $response = $ua->request($request, $d_gif)) {
			my $image = Image::Magick->new(magick=>'PNG');
			$image->Read($d_gif);
			#$image->Transparent(color=>"#000000");
			#$image->Opaque(color=>'#FFFFFF',fill=>'#000000');
			$image->Write(filename=>$d_png);
			$image->Write(filename=>$latest_png);
			#$blob = $image->ImageToBlob();
			#&blob_to_db($d_png);		
			unlink($d_gif);
			#unlink($d_png);
            print "ok\n";
        } else {
            print "error\n";
        }
    }	
	$sth->finish;
}

sub main {
    db_establish();
	if ((!$enable_nexrad) and ($ARGV[0] ne "composite")) {
		print "You have this script disabled in openweather.cfg.  Set 'enable_nexrad' to a value other than 0 to fetch NEXRAD images.\n";
		exit;
	}
	if ($ARGV[0] eq "DS.p19r0") {
		site("DS.p19r0");
	} elsif ($ARGV[0] eq "DS.78ohp") {
		site("DS.78ohp");
	} elsif ($ARGV[0] eq "DS.p20-r") {
		site("DS.p20-r");
	} elsif ($ARGV[0] eq "composite") {
		us_composite();
	} else {
		print "Invaild radar type!\n";
	}
	exit;
}

main();
