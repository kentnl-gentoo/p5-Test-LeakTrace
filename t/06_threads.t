#!perl -w

use strict;
use constant HAS_THREADS => eval{ require threads };

use Test::More;

BEGIN{
	if(HAS_THREADS){
		plan tests => 2;
	}
	else{
		plan skip_all => 'require threads';
	}
}

use threads;
use Test::LeakTrace;

# async touch a number of global values, e.g. *DynaLoader::CLONE/CLONE_SKIP.
async{
	my $a = 0;
	$a++;
}->join;

leaked_cmp_ok{
	async{
		my $a = 0;
		$a++;
	}->join;
} '<', 10;

async{
	not_leaked{
		my $a = 0;
		$a++;
	};
}->join();