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

###  паралелим
while (1) {
    my $devices = $device_obj->list();
    my $cmd = '';

    foreach my $device ( @{$devices} ){
        my $proc = `ps aux | grep perl | grep 'start.pl $device->{id}'`;
        unless ( $proc =~ /rc.d/gs ){
	    warn 'Start device '.$device->{device};
            $cmd .= "perl ./rc.d/start.pl $device->{id} &";
        } else {
	    warn 'Device '.$device->{device}.' work';
	}
    }
    #print Dumper $devices;
    `$cmd`;
    sleep 10;
}
