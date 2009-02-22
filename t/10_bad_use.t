#!perl -w

use strict;
use Test::More tests => 4;

use Test::LeakTrace;

for(1 .. 2){
	eval{
		my $count = leaked_count{
			my $count = leaked_count{
				my %a = (foo => 42);
				my %b = (bar => 3.14);

				$b{a} = \%a;
				$a{b} = \%b;
			};
		};
	};
	isnt $@, '', 'multi leaktrace';

	eval{
		leaktrace{
			my %a = (foo => 42);
			my %b = (bar => 3.14);

			$b{a} = \%a;
			$a{b} = \%b;
		} sub {
			die ['foo'];
		};
	};
	is_deeply $@, ['foo'], 'die in callback';
}