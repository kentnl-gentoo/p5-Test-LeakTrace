#!perl -w

use strict;

use Test::More tests => 1;
use Test::LeakTrace;

not_leaked{
	diag "in not_leaked";

	my @array;
	push @array, \@array;
};
