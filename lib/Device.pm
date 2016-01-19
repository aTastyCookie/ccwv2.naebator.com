package Device;

use strict;
use warnings;
use Data::Dumper;
use Cwd;
use Date::Format;
use File::Touch;
use File::Slurp;

sub new {
    my ( $package, $params ) = @_;
    return bless( $params , $package);
}

sub _clear_log {
    my ( $self, $log_file ) = @_;

    open my $fh ,">", $log_file;
    close $fh;
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
            #push @{$online_devices}, $device if $device->{work} != 1;
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

sub _get_mobile_by_id {
    my ( $self, $id ) = @_;

    my $connector = $self->{dbh};

    my $device = $connector->run( fixup => sub {
           return $_->selectrow_hashref(
               'SELECT * FROM devices WHERE id = ?',
               { Slice => {} },
               $id
           );
    });

    return $device;
   
}

sub _set_device_work_status {
    my ( $self, $device, $status ) = @_;
    my $connector = $self->{dbh};
    
    $connector->run( fixup => sub {
                return $_->do(
                    'UPDATE devices SET work = ?, updated = UNIX_TIMESTAMP() WHERE id = ?',
                        { Slice => {} },
                        $status,
                        $device->{id}
                );
    });
    
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
    my ( $self, $device ) = @_;

    #$self->_set_device_work_status($device, 1);
    my $log_file = $self->_create_log_file($device);
    $self->_start_logging({ device => $device, log_file => $log_file });
    $self->_execute_default_application( $device );
    $self->_sniff_log($log_file, $device);
    #$self->_set_device_work_status($device, 0);
}

sub _sniff_log {
    my ( $self, $log_file, $device ) = @_;
    # прочитаем последнюю строчку в логе при закрытии файла
    # спарсим файл снизу до нее
    my $last_filename = $log_file.'.last_row';
    my $last_line = read_file($last_filename);
    unless ( $last_line ) {
        $last_line = 0;
    }
    $self->_execute_default_application( $device );
    open my $fh, '<', $log_file or die "$log_file: $!";
    my $row;
    $self->_clear_log( $log_file );
    write_file( $last_filename, [0] ) ;
    while( <$fh> ) {
        $row = $.;
        if ( $row >= $last_line ) {
            ## Парсим с этого момента ##
            if ( $_ =~ /(Ad finished loading)/gs ){
                my $message = "start - Touch red bird on $device->{device}";
                `adb -s $device->{device} shell input tap 1145 2000`;
                $self->_log_event($device, $message);
                warn $message. "device_id: $device->{device}";
                $self->_execute_default_application( $device );
                sleep 5;
                `adb -s $device->{device} shell input tap 1145 2000`;
            }
        }
    }
    close $fh;
    write_file( $last_filename, [$row] ) ;
    
    my $attempts = 10;
    my $count_videos = 0;
    while ( $attempts >= 0 ) {
        warn "Attempts $attempts device_id: $device->{device}";
        sleep 2;

        $last_line = read_file($last_filename);
        open my $fh, '<', $log_file or die "$log_file: $!";
        my $row;
        while( <$fh> ) {
            $row = $.;
            if ( $row >= $last_line ) {
                ## Парсим с этого момента ##
                if ( $_ =~ /(Ad finished loading|Rewarded video ad placement|Open Video)/gs ){
                    my $message = "Start $attempts - Touch red bird on $device->{device}";
                    $self->_log_event($device, $message);
                    warn $message." device_id: $device->{device}";
                    $self->_execute_default_application( $device );
                    sleep 5;
                    `adb -s $device->{device} shell input tap 1145 2000`;
                    last;
                }
            }
        }
        close $fh;
        write_file( $last_filename, [$row] ) ;
	`adb -s $device->{device} shell input tap 1145 2000`;
        print "Waiting for the end of the advertisement on $device->{device}\n";
        sleep 5;

        my $state=0;
        $last_line = read_file($last_filename);

        open $fh, '<', $log_file or die "$log_file: $!";
        while( <$fh> ) {
            $row = $.;
            if ( $row >= $last_line ) {
                ## Парсим с этого момента ##
                if ( $_ =~ /Video Complete recorded|notifyResetComplete|finishComposingText/gs ){
                    my $message = "Found finish video device_id: $device->{device}";
                    $self->_log_event($device, $message);
                    warn $message;
                    warn $_;
                    sleep 2;
                    $self->_clear_log($log_file);
                    write_file( $last_filename, [0] ) ;
                    `adb -s $device->{device} shell input keyevent 4`;
                    $message = "Goto main screen";
                    $self->_log_event($device, $message);
                    warn $message;
                    $count_videos++;
                }
            }
        }
        
        close $fh;
        write_file( $last_filename, [$row] ) ;
        
        $attempts--;
        if ( $attempts == 0 && $count_videos == 0 ) {
            #ребутнется девайс надо слепануться на секунд 40
            `adb -s $device->{device} shell am startservice -n ru.gekos.naebator/.backend.changeDevice`;
            warn $device->{device}.' reboot wait loading';
            my $load = 0;
            my $load_status = 0;
            sleep 15;
            while ( $load != 1 ){
                $load_status = `adb -s $device->{device} shell getprop sys.boot_completed | tr -d '\r'`;
                $load = 1 if $load_status ne "";
                sleep 1;
            }
        }
    }
}

sub _log_event {
    my ( $self, $device, $message ) = @_;
    
    my $connector = $self->{dbh};
    
    $connector->run( fixup => sub {
                return $_->do(
                    'INSERT INTO logs(device_id, message, created, updated) VALUES(?,?,UNIX_TIMESTAMP(), UNIX_TIMESTAMP())',
                        { Slice => {} },
                        $device->{id},
                        $message
                );
    });
}


sub _execute_default_application {
    my ( $self, $device ) = @_;

    my $app = $self->{conf}{application};
    `adb -s $device->{device} shell monkey -p $app -c android.intent.category.LAUNCHER 1`;
    
}

sub _start_logging {
    my ( $self, $params ) = @_;

    #проверим на то что работает ли уже логгер на девайсе
    #unless ( `adb -s $params->{device}{device} shell ps | grep 'logcat -v threadtime'` ) {
        # если нет то запустим
        `adb -s $params->{device}{device} logcat -v threadtime > $params->{log_file} &`;
    #}
}

sub _create_log_file {
    my ( $self, $device ) = @_;
    
    my $template = $device->{device}.'-'.'%d-%m'; #'ZX1G427Z4M-18-01'
    my $log_file = getcwd.'/logs/'.time2str($template, time);

    unless ( -e $log_file ){
        touch( $log_file );
        #и создадим файл в который пишем номер последнeй строки
        touch( $log_file.'.last_row' );
    }
    #warn "Logging device $device->{device} to '$log_file'";
    return $log_file;
    
}


1;
