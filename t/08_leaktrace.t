#!perl -w

use strict;
use Test::More tests => 1;

use Test::LeakTrace;

my @refs;
leaktrace{
	my %a = (foo => 42);
	my %b = (bar => 3.14);

	$b{a} = \%a;
	$a{b} = \%b;
} sub {
	push @refs, \@_;
};

cmp_ok scalar(@refs), '>', 1;
