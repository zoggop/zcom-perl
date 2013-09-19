use Text::Markdown 'markdown';
use DateTime;

my $file = $ARGV[0];

open(FILE, $file);
my @lines = <FILE>;
close(FILE);

# read post 
my $l = 0;
my $title;
my $date;
my $first;
foreach my $line (@lines) {
	my $eval = $line;
	chomp($eval);
	if ((markdown($eval) =~ m/<h1>/) and ($title eq '')) {
		$title = $eval;
		$title =~ s/#//g; #remove header markdown
		$title =~ s/^\s+//; #remove leading spaces
		$title =~ s/\s+$//; #remove trailing spaces
		splice(@lines, $l, 1);
	} elsif ((markdown($eval) =~ m/<h2/) and ($date eq '')) {
		$date = $eval;
		$date =~ s/#//g; #remove header markdown
		$date =~ s/^\s+//; #remove leading spaces
		$date =~ s/\s+$//; #remove trailing spaces
		splice(@lines, $l, 1);
	} elsif ($first eq '') {
		my $possible = $eval;
		$possible =~ s/^\s+//; #remove leading spaces
		$possible =~ s/\s+$//; #remove trailing spaces
		if ($possible ne '') {
			$first = $possible;
		}
	}
	$l = $l + 1;
}

# if no title, create one
unless ($title) {
	if ($first) {
		print "no title, using first line of text\n";
		my @space = split(/ /, $first);
		my $w = 0;
		foreach $word (@space) {
			if ($w < 4) {
				$title = $title . $word . ' ';
				$w = $w + 1;
			}
		}
	} else {
		print "no title or any text. goodbye.\n";
		exit;
	}
}

# create a date from file modified date unless otherwise specified
unless($date) {
	my $epoch = (stat $file)[9];
	my $dt = DateTime->from_epoch( epoch => $epoch );
	my $year = $dt->year();
	my $month = $dt->month_name();
	my $day = $dt->day();
	my $hour = $dt->hour_12();
	my $min = sprintf("%02d", $dt->min());
	my $ampm = $dt->am_or_pm();
	$date = "$day $month $year $hour:$min $ampm";
	print "file last modified $date\n";
}

# this way, zcompile.pl deals with duplicate filename issues
my $shortname = TitleToShortName($date);

# create file
open(FILE, ">posts/$shortname.md");
print FILE "# $title\n";
print FILE "## $date\n";
print FILE "\n";
foreach $line (@lines) {
	print FILE $line;
}
close(FILE);

sub TitleToShortName() {
	if ($_[0]) {
		my $shortname= lc($_[0]);
		$shortname =~ s/[^a-z0-9]/_/g;
		return $shortname;
	} else {
		my $shortname = sprintf("%02d", $untitled);
		$untitled = $untitled + 1;
		return $shortname;
	}
}