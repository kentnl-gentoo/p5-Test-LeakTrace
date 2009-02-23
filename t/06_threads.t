#!perl -w

use strict;
use constant HAS_THREADS => eval{ require threads };

use Test::More;

BEGIN{
	if(HAS_THREADS){
		plan tests => 5;
	}
	else{
		plan skip_all => 'require threads';
	}
}

use threads;
use Test::LeakTrace;

leaked_cmp_ok{
	async{
		my $a = 0;
		$a++;
	}->join;
} '<', 10;

my $count = leaked_count {
	async{
		leaked_cmp_ok{
			my $a;
			$a = \$a;
		} '>', 0;

		not_leaked{
			my $a;
			$a++;
		};
	}->join;
};
cmp_ok $count, '<', 10, "(actually leaked: $count)";

async{
	not_leaked{
		my $a = 0;
		$a++;
	};
}->join();

