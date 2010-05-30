#!/usr/bin/perl

use strict;

my $file = shift @ARGV;
exit unless $file;

rename $file, "$file.old";

open my $in,  '<', "$file.old";
open my $out, '>', $file;

while ( my $line = readline $in ) {
    if ( $line =~ /^(DefaultRegionCountry|RegionName)/i ) {
        $line =~ s/�������/���./;
        $line =~ s/�����/�-�/;
        $line =~ s/���������� ����� - ���� ���������� �����/�� (����)/;
        $line =~ s/���������-���������� ����������/���������-��������/;
        $line =~ s/���������-���������� ����������/���������-��������/;
        $line =~ s/���������� �����/��/i;
        $line =~ s/���������� ���./��/i;
        $line =~ s/ �����//i;
        $line =~ s/(��|[^�]) ����������/$1/i;
        $line =~ s/ - ������//;
    }
    print $out $line;
}

close $in;
close $out;

unlink "$file.old";
