package Geo::Parse::OSM::Multipass;
use base qw{ Geo::Parse::OSM };

use strict;
use warnings;

use List::Util qw{ first };
use List::MoreUtils qw{ true first_index };

our $VERSION = '0.35';



my %role_type = (
    q{}      => 'outer',
    outer    => 'outer',
    border   => 'outer',
    exclave  => 'outer',
    inner    => 'inner',
    enclave  => 'inner',
);


sub new {
    my $class = shift;

    our $self = $class->SUPER::new( shift );

    $self->{latlon}         = {};
    $self->{waychain}       = {};
    $self->{mpoly}          = {};
    $self->{ways_to_load}   = {};

    our %param = @_;

    ## First pass - load multipolygon parameters

    my $osm_pass1 = sub {
        my ($obj) = @_;

        if ( $obj->{tag}->{type} =~ /multipolygon|boundary/ ) {
            # old-style multipolygons - load lists of inner rings
            if ( (true { $_->{role} eq 'outer' } @{ $obj->{members} }) == 1 ) {
                my $outer = first { $_->{role} eq 'outer' } @{ $obj->{members} };
                $self->{mpoly}->{$outer->{ref}} = 
                    [ map { $_->{ref} } grep { $_->{role} eq 'inner' } @{ $obj->{members} } ];
            }
            # advanced multipolygons - load lists of ways
            for my $member ( @{ $obj->{members} } ) {
                next unless $member->{type} eq 'way';
                next unless exists $role_type{ $member->{role} };
                $self->{ways_to_load}->{ $member->{ref} } = 1;
            }
        }

        &{ $param{pass1} }( $obj )  if exists $param{pass1};
    };

    $self->SUPER::parse( $osm_pass1, only => 'relation' );

    ## Second pass - load necessary primitives

    $self->seek_to(0);

    &{ $param{between} }()  if exists $param{between};

    my $osm_pass2 = sub {
        my ($obj) = @_;

        if ( $obj->{type} eq 'node' ) {
            $self->{latlon}->{ $obj->{id} } = pack 'Z*Z*', $obj->{lat}, $obj->{lon};
        }
        elsif ( $obj->{type} eq 'way' && exists $self->{ways_to_load}->{$obj->{id}} ) {
            $self->{waychain}->{ $obj->{id} } = $obj->{chain};
            delete $self->{ways_to_load}->{$obj->{id}};
        }

        &{ $param{pass2} }( $obj )  if exists $param{pass2};
    };

    $self->SUPER::parse( $osm_pass2 );

    $self->seek_to(0);

    bless ($self, $class);
    return $self;
}


sub parse {

    our $self = shift;
    our $callback = shift;

    my $parse_extent = sub {
        my ($obj) = @_;

        # old-style multipolygons
        if ( $obj->{type} eq 'way' && exists $self->{mpoly}->{ $obj->{id} }
                && $obj->{chain}->[0] eq $obj->{chain}->[-1] ) {
            $obj->{outer} = [ [ @{$obj->{chain}} ] ];
            # $obj->{outer} = [ $obj->{chain} ];
            for my $inner ( @{ $self->{mpoly}->{ $obj->{id} } } ) {
                next unless exists $self->{waychain}->{$inner};
                next unless $self->{waychain}->{$inner}->[0] eq $self->{waychain}->{$inner}->[-1];
                push @{ $obj->{inner} }, $self->{waychain}->{$inner};
            }
        }

        # advanced multipolygons
        if ( $obj->{type} eq 'relation' && $obj->{tag}->{type} =~ /multipolygon|boundary/ ) {

            for my $contour_type ( 'outer', 'inner' ) {
    
                my @list =
                    grep { exists $self->{waychain}->{$_} }
                    map { $_->{ref} }
                    grep { $_->{type} eq 'way'
                        && exists $role_type{$_->{role}}
                        && $role_type{$_->{role}} eq $contour_type }
                    @{ $obj->{members} };

                LIST:
                while ( @list ) {

                    my $id = shift @list;
                    my @contour = @{ $self->{waychain}->{$id} };

                    CONTOUR:
                    while ( 1 ) {
                        # closed way
                        if ( $contour[0] eq $contour[-1] ) {
                            push @{ $obj->{$contour_type} }, [ @contour ];
                            next LIST;
                        }

                        my $add = first_index { $contour[-1] eq $self->{waychain}->{$_}->[0] } @list;
                        if ( $add > -1 ) {
                            pop @contour;
                            push @contour, @{ $self->{waychain}->{ $list[$add] } };

                            splice  @list, $add, 1;
                            next CONTOUR;
                        }
            
                        $add = first_index { $contour[-1] eq $self->{waychain}->{$_}->[-1] } @list;
                        if ( $add > -1 ) {
                            pop @contour;
                            push @contour, reverse @{ $self->{waychain}->{ $list[$add] } };

                            splice  @list, $add, 1;
                            next CONTOUR;
                        }

                        last CONTOUR;
                    } #contour
                } # members
            } # outers/inners
        } # advanced multipolygon

        &$callback( @_ );
    };
    
    $self->SUPER::parse( $parse_extent, @_ );    
}

sub latlon {
    my $self = shift;
    my ($node_id) = @_;

    return exists $self->{latlon}->{$node_id}
        ? ( unpack 'Z*Z*', $self->{latlon}->{$node_id} )
        : undef;
}


1;

=head1 NAME

Geo::Parse::OSM::Multipass - Multipass OpenStreetMap file parser


=head1 SYNOPSIS

Geo::Parse::OSM::Multipass extends Geo::Parse::OSM class to resolve geometry.

    use Geo::Parse::OSM::Multipass;

    my $osm = Geo::Parse::OSM::Multipass->new( 'planet.osm.gz' );
    $osm->seek_to_relations;
    $osm->parse( sub{ warn $_[0]->{id}  if  $_[0]->{user} eq 'Alice' } );


=head1 METHODS

=head2 new

    my $osm = Geo::Parse::OSM::Multipass->new( 'planet.osm' );

Creates parser instance and makes two passes:
1 - only relations, create the list of multipolygon parts
2 - load those parts and nodes

You can add extra custom callback function:

    my $osm = Geo::Parse::OSM::Multipass->new( 'planet.osm', pass1 => sub{ ... } );

* pass1 - for every object during 1st pass
* pass2 - same for second pass
* between - before 2nd pass

=head2 parse

Same as in Geo::Parse::OSM, but callback object has additional fields for multipolygon objects:

* outer - list of outer rings (ring is a closed list of node ids)
* inner - inner rings

=head2 latlon

Returns coordinates of node (after 2nd pass)

    my ($lat,$lon) = $osm->latlon( '1234578' );


=head1 AUTHOR

liosha, C<< <liosha at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-geo-parse-osm at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Geo-Parse-OSM>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Geo::Parse::OSM


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Geo-Parse-OSM>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Geo-Parse-OSM>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Geo-Parse-OSM>

=item * Search CPAN

L<http://search.cpan.org/dist/Geo-Parse-OSM/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2010 liosha.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut
