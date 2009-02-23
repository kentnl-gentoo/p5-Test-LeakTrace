#!perl -w

use strict;
use Test::More tests => 8;

use Test::LeakTrace;

{
	package Foo;
	sub new{
		return bless {}, shift;
	}
}

not_leaked {
	my %a;
	my %b;

	$a{b} = 1;
	$b{a} = 2;
} 'not leaked';

not_leaked{
	my $o = Foo->new();
	$o->{bar}++;
};

not_leaked{
	# empty
};

leaked_cmp_ok{
	my $a;
	$a++;
} '==', 0;

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

