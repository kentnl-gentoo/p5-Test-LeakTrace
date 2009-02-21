#!perl -w

use strict;
use Test::More tests => 2;

use Test::LeakTrace qw(leaked_info);

my @info = leaked_info{
	my %a = (foo => 42);
	my %b = (bar => 3.14);

	$b{a} = \%a;
	$a{b} = \%b;
};

cmp_ok(scalar(@info), '>', 1) or do{
	require Data::Dumper;
	diag(Data::Dumper->Dump([\@info], ['*info']));
};

my($si) = grep { ref($_->[0]) eq 'SCALAR' and ${$_->[0]} eq 42 } @info;
use Data::Dumper;
is_deeply $si, [\42, __FILE__, 9], 'state info';

