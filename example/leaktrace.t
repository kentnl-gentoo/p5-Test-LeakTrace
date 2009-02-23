#!perl -w
# an example for standard test scripts

use strict;

use constant HAS_LEAKTRACE => eval{ require Test::LeakTrace };
use Test::More HAS_LEAKTRACE ? (tests => 1) : (skip_all => 'require Test::LeakTrace');

use Test::LeakTrace;

use Class::Monadic;

leaked_cmp_ok{
	my $o = bless {};

	Class::Monadic->initialize($o)->add_method(foo => sub{
		my $i = 0;
		$i++;
	});
	$o->foo();

} '<=', 1;

