#!perl -w
# a test script template

use strict;

use constant HAS_LEAKTRACE => eval{ require Test::LeakTrace };
use Test::More HAS_LEAKTRACE ? (tests => 1) : (skip_all => 'require Test::LeakTrace');

use Test::LeakTrace;

use threads; # for example

leaked_cmp_ok{

	async{
		my $i;
		$i++;
	}->join();

} '<', 1, 'threads->create->join';

