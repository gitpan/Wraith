#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 14;
use Wraith qw ( $many $token $literal $literals );

my $res_literal = $literal->('a')->('aaab');
ok($res_literal->[0]->[0]->[0] eq 'a');
ok($res_literal->[0]->[1] eq 'aab');

my $res_literals = $literals->('ab')->('baab');
ok($res_literals->[0]->[0]->[0] eq 'b');
ok($res_literals->[0]->[1] eq 'aab');

my $res_many = $many->($literal->('3'))->('334');
ok(scalar @$res_many eq 3);

my $res_then = ($literal->('3') >> $literal->('4'))->('34');
ok($res_then->[0]->[0]->[0] eq '3');
ok($res_then->[0]->[0]->[1] eq '4');
ok($res_then->[0]->[1] eq '');
my $nopass_then = ($literal->('3') >> $literal->('4'))->('45');
ok(scalar @$nopass_then eq 0);

my $res_alt = ($literal->('3') | $literal->('4'))->('34');
ok($res_alt->[0]->[0]->[0] eq '3');
ok($res_alt->[0]->[1] eq '4');
my $nopass_alt = ($literal->('3') | $literal->('4'))->('54');
ok(scalar @$nopass_alt eq 0);

my $res_using = ( ($literal->('3')) ** sub { [ $_[0]->[0] + 1 ] } )->('34');
ok($res_using->[0]->[0]->[0] eq '4');
ok($res_using->[0]->[1] eq '4');
