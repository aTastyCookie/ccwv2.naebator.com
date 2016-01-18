package DB;

use strict;
use warnings;
use Data::Dumper;

use DBIx::Connector;

sub new {
    my $package = shift;
    return bless({}, $package);
}

sub connect {
    my ( $self, $conf ) = @_;

    my $conn = DBIx::Connector->new(
        $conf->{dsn},
        $conf->{user},
        $conf->{password},
        {
            RaiseError => 1,
            mysql_enable_utf8 => 1
        }
    );
    
    return $conn;
}

1;