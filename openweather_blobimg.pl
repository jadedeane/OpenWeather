#!/usr/bin/env perl
# Open Weather 0.22
# Script: openweather_nexrad.pl rev 2
# Developer: Jade E. Deane (jade.deane@gmail.com)
# Purpose: Fetch NEXRAD information.
#
# License: Distributed under the GNU General Public License.

use strict;

use CGI qw(:standard escapeHTML);
use DBI;
use Image::Magick;

# Config.
my %openweather;
my $Configfile = "";
open (CONF,$Configfile) or die "Could not open config file $Configfile: $! \n";
my $code = join ('', <CONF>);
close (CONF);
eval $code;

# Global items.
my $q = new CGI;
my $dbh;
my $loc = $q->param('loc');
my $rtype = $q->param('rtype');
my $cnum = $q->param('cnum');
my $db_type = $openweather{'db_type'};
my $db_username = $openweather{'db_username'};
my $db_password = $openweather{'db_password'};
my $db_hostname = $openweather{'db_hostname'};
my $db_database = $openweather{'db_database'};

sub db_establish {
    my %DBConnectOpts = ( PrintError => 0, RaiseError => 0 );
    my $DSN = "DBI:$db_type:$db_database:$db_hostname";
    $dbh = DBI->connect($DSN, $db_username, $db_password, \%DBConnectOpts) or db_error();
}

sub main {
	db_establish();
	my $blob;
	my @blob;
	my $sth1 = $dbh->prepare("select image from radimg where loc = '$loc' and rtype = '$rtype' and cnum = '$cnum'") 
		or die "Prepare Fails: ", DBI::errstr, "\n";
	my $re = $sth1->execute or print"Error ".DBI::errstr."\n";
	my $r = 0;
	($blob) = $sth1->fetchrow_array;
	$sth1->finish;
	$dbh->disconnect();
	my $image = Image::Magick->new(magick=>'png');
	select(STDOUT); $| = 1;
	binmode STDOUT;
	print $q->header(-type=>'image/png');
	$image->BlobToImage($blob);
	$image->Write( "png:-" );
	undef $image;
}

&main();
