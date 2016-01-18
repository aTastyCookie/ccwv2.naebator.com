package Device;

use strict;
use warnings;
use Data::Dumper;
use Cwd;
use Date::Format;
use File::Touch;

sub new {
    my ( $package, $params ) = @_;
    return bless( $params , $package);
}

sub list {
    my ( $self ) = @_;

    my $connector = $self->{dbh};
    
    my $know_devices = $self->_get_know_mobiles();
    my $adb_devices = $self->_get_adb_devices();
    # проверка на новые девайсы
    foreach my $device ( @{$adb_devices} ) {
        my $exist_flag  = 0;
        
        foreach my $know_device ( @{$know_devices} ){
            $exist_flag = 1 if $know_device->{device} eq $device;
        }

        if ( $exist_flag ) {
            $connector->run( fixup => sub {
                return $_->do(
                    'UPDATE devices SET updated = UNIX_TIMESTAMP(), status = 1 WHERE device = ?',
                        { Slice => {} },
                        $device
                );
            });
        } else {
            $connector->run( fixup => sub {
                return $_->do(
                    'INSERT INTO devices(device,created,updated) VALUES(?,UNIX_TIMESTAMP(), UNIX_TIMESTAMP())',
                        { Slice => {} },
                        $device
                );
            });
        }
    }
    #обновим know_devices т.к. девайс мог добавиться
    $know_devices = $self->_get_know_mobiles();
    #чекалка на оффлайность труб
    return $self->_check_offline_device({ know_devices => $know_devices, adb_devices => $adb_devices });
}

#вернет массив телефонов с которыми можно работать
sub _check_offline_device {
    my ( $self, $params ) = @_;

    my $connector = $self->{dbh};
    my $online_devices = [];

    foreach my $device ( @{$params->{know_devices}} ){
        unless ( grep( /^$device->{device}$/, @{$params->{adb_devices}} ) ) {
            $connector->run( fixup => sub {
                return $_->do(
                    'UPDATE devices SET status = 0, updated = UNIX_TIMESTAMP() WHERE id = ?',
                        { Slice => {} },
                        $device->{id}
                );
            });
        } else {
            push @{$online_devices}, $device;
        }
    }

    return $online_devices;
    
}

#вернет массив хэшей известных телефонов
sub _get_know_mobiles {
    my ( $self ) = @_;

    my $connector = $self->{dbh};

    my $know_devices = $connector->run( fixup => sub {
           return $_->selectall_arrayref(
               'SELECT * FROM devices',
               { Slice => {} },
           );
    });

    return $know_devices;
   
}

#вернет массив девайсов из adb devices
sub _get_adb_devices {
    my ( $self ) = @_;
    my @adb_devices_cmd = `adb devices`;

    my $devices;

    foreach my $device ( @adb_devices_cmd ){
        if ( $device =~ /device$/ ) {
            $device =~ s/^(.*?)\s/$1/;
            push @{$devices}, $1;
        }
    }

    return $devices;
}

sub start {
    my ( $self, $devices ) = @_;

    foreach my $device ( @{$devices} ){
        my $log_file = $self->_create_log_file($device);
        $self->_start_logging({ device => $device, log_file => $log_file });
        $self->_execute_default_application( $device );
        $self->_sniff_log($log_file, $device);
    }

}

sub _sniff_log {
    my ( $self, $log_file, $device ) = @_;

    open Tail, "/usr/bin/tail -f $log_file |" or die "Tailf failed: $!\n";
    while (<Tail>){
        if ( $_ =~ '/Ad finished loading/gs' ){
            print Dumper "start - Touch red bird on $device->{device}";
        }
    }
}

sub _execute_default_application {
    my ( $self, $device ) = @_;

    my $app = $self->{conf}{application};
    `adb -s $device->{device} shell monkey -p $app -c android.intent.category.LAUNCHER 1`;
    
}

sub _start_logging {
    my ( $self, $params ) = @_;

    #проверим на то что работает ли уже логгер на девайсе
    unless ( `adb -s $params->{device}{device} shell ps | grep 'logcat -v threadtime'` ) {
        # если нет то запустим
        `adb -s $params->{device}{device} logcat -v threadtime > $params->{log_file} &`;
    }
}

sub _create_log_file {
    my ( $self, $device ) = @_;
    
    my $template = $device->{device}.'-'.'%d-%m'; #'ZX1G427Z4M-18-01'
    my $log_file = getcwd.'/logs/'.time2str($template, time);;

    unless ( -e $log_file ){
        warn 'Create log file '.$log_file;
        touch( $log_file );
    }
    warn "Logging device $device->{device} to '$log_file'";
    return $log_file;
    
}


1;
