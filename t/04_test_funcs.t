#!perl -w

use strict;
use Test::More tests => 5;

use Test::LeakTrace;

not_leaked {
	my %a;
	my %b;

	$a{b} = 1;
	$b{a} = 2;
} 'not leaked';

sub leaked{
	my %a;
	my %b;

	$a{b} = \%b;
	$b{a} = \%a;
}

leaked_cmp_ok \&leaked, '<',  10;
leaked_cmp_ok \&leaked, '<=', 10;
leaked_cmp_ok \&leaked, '>',   0;
leaked_cmp_ok \&leaked, '>=',  1;

