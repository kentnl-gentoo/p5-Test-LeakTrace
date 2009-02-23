#!perl -w

use strict;
use Test::More tests => 1;

use Test::LeakTrace ();

my $content = do{
	local $/;
	open my $in, '<', $INC{'Test/LeakTrace.pm'};
	<$in>;
};

my($synopsis) = $content =~ m{
	^=head1 \s+ SYNOPSIS
	(.+)
	^=head1 \s+ DESCRIPTION
}xms;

ok eval("sub{ $synopsis }"), 'syntax ok' or diag $@;
