use strict;
use warnings;
use inc::Module::Install;
use Config;

name 'Test-LeakTrace';
all_from 'lib/Test/LeakTrace.pm';

if($Config{ccflags} =~ /-DPURIFY/){
	warn <<'MSG';
Test::LeakTrace is not available on this perl, because arena allocation
mechanism Test::LeakTrace depends on is disabled in this perl by -DPURITY.

See also perldoc perlhack.
MSG
	exit;
}

requires 'Exporter'   => 5.57;
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
