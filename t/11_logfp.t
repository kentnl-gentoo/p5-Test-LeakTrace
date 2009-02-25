#!perl -w

use strict;
use Test::More tests => 13;

use Test::LeakTrace qw(:util);

my $content = '';

sub t{
	open my $logfp, '>', \$content;
	local *STDERR = $logfp;
	leaktrace{
		my @array;
		push @array, 42, \@array;
	} shift;
}

t(-simple);
like $content, qr/from ${\__FILE__} line 15\./, -simple;
unlike $content, qr/15:\t\tpush \@array/, -lines;
unlike $content, qr/REFCNT/, -sv_dump;

t(-lines);
like $content, qr/from ${\__FILE__} line 15\./, -simple;
like $content, qr/15:\t\tpush \@array/, -lines;
unlike $content, qr/REFCNT/, -sv_dump;

t(-sv_dump);
like $content, qr/from ${\__FILE__} line 15\./, -simple;
unlike $content, qr/15:\t\tpush \@array/, -lines;
like $content, qr/REFCNT/, -sv_dump;

t(-verbose);
like $content, qr/from ${\__FILE__} line 15\./, -simple;
like $content, qr/15:\t\tpush \@array/, -lines;
like $content, qr/REFCNT/, -sv_dump;

t(-silent);
is $content, '', -silent;
