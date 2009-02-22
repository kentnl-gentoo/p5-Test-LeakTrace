#!perl -w

use strict;
use Test::More tests => 6;

use Test::LeakTrace;

for(1 .. 2){
	leaked_cmp_ok{
		eval q{
			my %a = (foo => 42);
			my %b = (bar => 3.14);

			$b{a} = \%a;
			$a{b} = \%b;
		};
	} '>', 0;

	my @info = 	leaked_info { eval q{
			my %a = (foo => 42);
			my %b = (bar => 3.14);

			$b{a} = \%a;
			$a{b} = \%b;
		};
	};

	cmp_ok scalar(@info), '>', 0;

	@info = leaked_info{
		use Class::Struct;

		struct "Foo$_" => { bar => '$' };

		my $foo = "Foo$_"->new();
		$foo->bar(42);
	};

	cmp_ok scalar(@info), '>', 0, "create Foo$_";
}
