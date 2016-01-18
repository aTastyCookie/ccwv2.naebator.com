package Device;

use strict;
use warnings;
use Data::Dumper;

sub new {
    my ( $package, $params ) = @_;
    return bless( $params , $package);
}

sub list {
    my ( $self ) = @_;

    my $connector = $self->{dbh};
    
    my $know_devices = $connector->run( fixup => sub {
            return $_->selectall_arrayref(
                'SELECT * FROM devices',
                { Slice => {} },
            );
    });
    
    print Dumper $know_devices;
    

}

1;