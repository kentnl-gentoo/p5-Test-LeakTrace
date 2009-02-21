use strict;
use warnings;
use inc::Module::Install;

name 'Test-LeakTrace';
all_from 'lib/Test/LeakTrace.pm';


requires 'Test::More' => 0.62;

tests 't/*.t';
author_tests 'xt';

WriteMakefile(
	OBJECT => '$(O_FILES)',

	clean  => {FILES => q(
		Test-LeakTrace-* *.stackdump
		*.gcda *.gcno *.gcov
		nytprof *.out
		cover_db
	)},
);
