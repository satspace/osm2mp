package TextFilter;

# ABSTRACT: text filter chain

# $Id$


use 5.010;
use strict;
use warnings;
use utf8;

use autodie;
use Carp;
use Encode;


our %PREDEFINED_FILTER = (
    upcase      => sub { return uc shift },
    translit    => sub { require Text::Unidecode; return Text::Unidecode::unidecode( shift ) },
);




=method new

    my $finter_chain = TextFilter->new();

Constructor

=cut

sub new {
    my ($class) = @_;
    return bless { chain => [] }, $class;
}


=method add_filter

    $filter_chain = add_filter( $filter_name );
    $filter_chain = add_filter( $filter_sub );

=cut

sub add_filter {
    my ($self, $filter) = @_;

    $filter = $PREDEFINED_FILTER{$filter}  if $PREDEFINED_FILTER{$filter};
    croak "Bad filter: $filter"  if ref $filter ne 'CODE';

    push @{ $self->{chain} }, $filter;
    return;
}


=method add_perlio_filter

    $filter_chain->add_perlio_filter( $filter );

wrapper for perlio filters - slow!

=cut

sub add_perlio_filter {
    my ($self, $perlio) = @_;
    my $package = "PerlIO::via::$perlio";

    eval "require $package" or eval "require $perlio"
        or croak "Invalid perlio filter: $package";

    return $self->add_filter( sub {
            my $dump = q{};
            open my $fh, ">:utf8:via($perlio):utf8", \$dump;
            print {$fh} shift();
            close $fh;

            return decode 'utf8', $dump;
        });
}


=method add_table_filter

    $filter_chain->add_table_filter( $filename );
    $filter_chain->add_table_filter( { $bad_letter => $good_letter, ... } );

=cut

sub add_table_filter {
    my ($self, $table) = @_;

    if ( !ref $table ) {
        require YAML;
        $table = YAML::LoadFile( $table );
    }

    return $self->add_filter( sub {
            return join q{}, map { $table->{$_} // $_ } unpack '(Z)*', shift;
        });
}


=method add_gme_filter

    $filter_chain->add_gme_filter( $filename );

=cut

sub add_gme_filter {
    my ($self, $file) = @_;

    my $encoding = 'utf8';
    my %table;

    open my $in, '<', $file;
    while ( defined( my $line = readline $in ) ) {
        $line =~ s/ ^ \xEF \xBB \xBF //xms;
        $line =~ s/ \s* $ //xms;

        if ( my ($cp_code) = $line =~ / ^ \.CODEPAGE \s+ (\d+) /xms ) {
            $encoding = "cp$cp_code";
        }

        next if $line =~ / ^ (?: \s | ; | \# | \. | $ ) /xms;

        my ($from, $to) = split "\t", decode( $encoding, $line );
        $table{$from} = $to;
    }
    close $in;

    my $re_text;
    eval {
        require Regexp::Assemble;
        $re_text = Regexp::Assemble->new()->add( map { quotemeta $_ } keys %table )->re();
    }
    or eval {
        $re_text = join q{|}, map { quotemeta $_ } sort { length $b <=> length $a } keys %table;
        require Regexp::Optimizer;
        $re_text = Regexp::Optimizer->new()->optimize($re_text);
    }; 
    
    my $re = qr/($re_text)/;

    my $translator = sub {
        my ($str) = @_;
        $str =~ s/$re/$table{$1}/gxms;
        return $str;
    };

    return $self->add_filter( $translator );
}


=method apply

    my $filtered_text = $filter_chain->apply( $text );

=cut

sub apply {
    my ($self, $text) = @_;

    for my $filter ( @{ $self->{chain} } ) {
        $text = $filter->($text);
    }
    return $text;
}





1;
