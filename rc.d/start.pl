#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;

use lib './lib';

use DB;
use Device;
use YAML::XS qw(LoadFile);
### read config ###
my $config = LoadFile('./etc/conf.yml');
###################

### conn to db ###
my $db_obj = new DB;
my $dbh = $db_obj->connect($config->{db});
##################

### devices obj ###
my $device_obj = new Device( { dbh => $dbh, conf => $config } );

my $device_id = $ARGV[0];

### получим по id девайс
my $device_info = $device_obj->_get_mobile_by_id( $device_id );

$device_obj->start($device_info);