# Open Weather v0.22
# File: openweather.sql rev 9
# Developer: Jade E. Deane (jade.deane@gmail.com)
# Purpose: Build initial database tables.
#
# License: Distributed under the GNU General Public License.

# Sites.
DROP TABLE IF EXISTS si;
CREATE TABLE si (
    icao CHAR(4) PRIMARY KEY NOT NULL DEFAULT '',
    b_num CHAR(2) NOT NULL DEFAULT '--',
    s_num CHAR(3) NOT NULL DEFAULT '---',
    place VARCHAR(255) NOT NULL DEFAULT '',
    state CHAR(2) NOT NULL DEFAULT '',
    country VARCHAR(255) NOT NULL DEFAULT '',
    wmo_region VARCHAR(7) NOT NULL DEFAULT '',
    s_latitude CHAR(9) NOT NULL DEFAULT '',
    s_longitude CHAR(9) NOT NULL DEFAULT '',
    a_latitude CHAR(9) NOT NULL DEFAULT '',
    a_longitude CHAR(9) NOT NULL DEFAULT '',
    elevation CHAR(20) NOT NULL DEFAULT '',
    ua_elevation CHAR(20) NOT NULL DEFAULT '',
    rbsn CHAR(1) NOT NULL DEFAULT ''
);
DROP INDEX place_idx;
CREATE INDEX place_idx ON si (place);

# METAR cycles.
DROP TABLE IF EXISTS reports_cur;
CREATE TABLE reports_cur (
    report_id  INT PRIMARY KEY NOT NULL AUTO_INCREMENT,
    cycle char(3) NOT NULL DEFAULT '',
    raw_report VARCHAR(255) NOT NULL DEFAULT '',
    site CHAR(4) NOT NULL DEFAULT '',
    date_time VARCHAR(255) NOT NULL DEFAULT '',
    wind VARCHAR(255) NOT NULL DEFAULT '',
    visibility VARCHAR(255) NOT NULL DEFAULT '',
    clouds VARCHAR(255) NOT NULL DEFAULT '',
    temperature VARCHAR(255) NOT NULL DEFAULT '',
    pressure VARCHAR(255) NOT NULL DEFAULT '',
    condition VARCHAR(255) NOT NULL DEFAULT '',
    remarks VARCHAR(255) NOT NULL DEFAULT '',
    created DATETIME NOT NULL DEFAULT 'NOW()'
);

# Radar images.
DROP TABLE IF EXISTS radimg;
CREATE TABLE radimg (
	loc VARCHAR(7) NOT NULL DEFAULT '',
	rtype VARCHAR(10) NOT NULL DEFAULT '',
	cnum DECIMAL(2,0) NOT NULL DEFAULT '0',
	dldate DATETIME NOT NULL DEFAULT '',
	image BLOB NOT NULL DEFAULT ''	
);

# Forecasts.
DROP TABLE IF EXISTS forecasts;
CREATE TABLE forecasts (
	forecast_id INT PRIMARY KEY NOT NULL AUTO_INCREMENT,
	city CHAR(255) NOT NULL DEFAULT '',
	issued CHAR(255) NOT NULL DEFAULT '',
	chunk0 VARCHAR(255) NOT NULL DEFAULT '',
	chunk1 VARCHAR(255) NOT NULL DEFAULT '',
	chunk2 VARCHAR(255) NOT NULL DEFAULT '',
	chunk3 VARCHAR(255) NOT NULL DEFAULT '',
	chunk4 VARCHAR(255) NOT NULL DEFAULT ''
);

# Zip codes.
DROP TABLE IF EXISTS zip;
CREATE TABLE zip (
    zip_code CHAR(5) PRIMARY KEY NOT NULL DEFAULT '',
    longitude CHAR(10) NOT NULL DEFAULT '',
    latitude CHAR(10) NOT NULL DEFAULT ''
);

# Time zones.
DROP TABLE IF EXISTS tz;
CREATE TABLE tz (
    zone CHAR(1) PRIMARY KEY NOT NULL DEFAULT '',
    offset CHAR(3) NOT NULL DEFAULT '',
    bound_w CHAR(3) NOT NULL DEFAULT '',
    bound_e CHAR(3) NOT NULL DEFAULT ''
);

# Distance storage.
DROP TABLE IF EXISTS distance_temp;
CREATE TABLE distance_temp (
	id INT PRIMARY KEY NOT NULL AUTO_INCREMENT,
	dk VARCHAR(255) NOT NULL DEFAULT '',
	icao CHAR(4) NOT NULL DEFAULT '',
	place VARCHAR(255) NOT NULL DEFAULT '',
	state VARCHAR(255) NOT NULL DEFAULT '',
	distance INT(255) NOT NULL DEFAULT '0'
);

# Load data.
load data local infile "nsd_cccc.txt" into table si fields terminated by ';';
load data local infile "time_zones.txt" into table tz fields terminated by ';';
load data local infile "zip_codes.txt" into table zip fields terminated by ';';
