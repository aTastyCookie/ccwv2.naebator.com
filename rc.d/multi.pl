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

### с этого момента начнется вся карулесь с while и sleep

while(1){
    my $list = $device_obj->list();

    $device_obj->start($list);

    sleep 3;
}
