# zoggop dot com static website compiler
use File::Copy;
use Date::Parse;
use Text::Markdown 'markdown';
use Date::Calc qw(Delta_Days);
use IO::File;
use Digest::MD5 qw(md5_hex);
use File::Slurp;
use DateTime::Format::Natural;

# config variables
my $frontPageDays = 7; # how many days beyond the first post to display on the front page

# command line arguments
my %CLARG = {};
foreach my $arg (@ARGV) {
	$CLARG{$arg} = 1;
}

if ($CLARG{'all'}) {
	if (-e "posts.inventory") { unlink "posts.inventory"; }
	if (-e "posts.newest") { unlink "posts.newest"; }
}

# read last checksums and dates to compare against
my %lastCheckSums;
my %lastDates;
if (-e "posts.inventory") {
	open(FILE, "posts.inventory");
	@cslines = <FILE>;
	close(FILE);
	my $a = 0;
	my $filename;
	my $checksum;
	foreach my $line (@cslines) {
		chomp($line);
		if ($a == 0) {
			$filename = $line;
			$a = 1; 
		} elsif ($a == 1) {
			$lastCheckSums{$filename} = $line;
			$a = 2;
		} else {
			$lastDates{$filename} = $line;
			$a = 0;
		}
	}
}

# ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

my $newestPost = GetLastNewestPost();

# read post markdown checksums to find new posts
opendir(DIR, "posts");
@postfiles = readdir(DIR);
closedir(DIR);
my @newPosts;
foreach my $postfile (@postfiles) {
	if (($postfile ne '.') and ($postfile ne '..')) {
		print "$postfile\n";
		my $checksum = md5_hex(read_file("posts/$postfile"));
		print "$checksum\n";
		if (($checksum ne $lastCheckSums{$postfile}) or ($CLARG{'all'})) {
			push(@newPosts, $postfile);
		}
		if ($newestPost eq '') { $newestPost = $postfile; }
	}
}

# create build directory if not existant
unless (-d 'build') { mkdir ('build'); }

# read new posts and create their post pages
my @pages;
my %pageRef;
my %postDates;
foreach my $key (keys %lastDates) { $postDates{$key} = $lastDates{$key}; }
my %checkSums;
foreach my $key (keys %lastCheckSums) { $checkSums{$key} = $lastCheckSums{$key}; }
my $ref = 0;
foreach my $postfile (@newPosts) {
	my $page = {};
	($page->{'Title'}, $page->{'Date'}, $page->{'Content'}) = ReadPost($postfile);
	print "before $postfile, $page->{'Title'}, $page->{'Date'}\n";
	$page->{'ShortName'} = $page->{'Title'};
	$page->{'ShortName'} = lc($page->{'ShortName'});
	$page->{'ShortName'} =~ s/ /_/g;
	# $page->{'ShortName'} = $page->{'ShortName'} . $page->{'Date'};
	my $suffix = 1;
	while ($lastCheckSums{"$page->{'ShortName'}.md"}) {
		$page->{'ShortName'} = $page->{'ShortName'} . $suffix;
		$suffix = $suffix + 1;
	}
	move("posts/$postfile", "posts/$page->{'ShortName'}.md");
	$postfile = "$page->{'ShortName'}.md";
	$checkSums{"$postfile"} = md5_hex(read_file("posts/$postfile"));
#	my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($page->{'Date'});
#	($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($lastDate{$newestPost});
	if (GetDateNumber($page->{'Date'}) > GetDateNumber($lastDate{$newestPost})) {
		$newestPost = $postfile;
	}
	print "after $postfile, $page->{'Title'}, $page->{'Date'}\n";
	$postDates{"$postfile"} = $page->{'Date'};
	$pages[$ref] = $page;
	$pageRef{$postfile} = $ref;
	BuildPostPage($postfile);
	$ref = $ref + 1;
}

# build index
my %frontPageDates;
# find posts within $frontPageDays old
print "newest $newestPost $postDates{$newestPost}\n";
my $parser = DateTime::Format::Natural->new;
my $date_string  = $parser->extract_datetime($postDates{$newestPost});
my $dt = $parser->parse_datetime($date_string);
my @newestYearMonthDay = ($dt->year, $dt->month, $dt->day);
my $newestDateNumber = GetDateNumber($postDates{$newestPost});
foreach my $key (keys %checkSums) { print "key: $key\n"; }
foreach my $postfile (keys %checkSums) {
	print "$postDates{$newestPost}\n";
#	my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($dates{$postfile});
	print "$postfile $postDates{$postfile}\n";
	my $parser = DateTime::Format::Natural->new;
 	my $date_string  = $parser->extract_datetime($postDates{$postfile});
 	my $dt = $parser->parse_datetime($date_string);
	my @ymd = ($dt->year, $dt->month, $dt->day);
	print("$ymd[0] $ymd[1] $ymd[2] compared to newest $newestYearMonthDay[0] $newestYearMonthDay[1] $newestYearMonthDay[2]\n");
	my $daysold = Delta_Days(@newestYearMonthDay, @ymd);
	print ("days old $daysold\n");
	if ($daysold <= $frontPageDays) {
		print "$postfile within front page\n";
		my $datenumber = GetDateNumber($postDates{$postfile});
		$frontPageDates{$postfile} = $datenumber;
	}
}
# sort posts
my @frontPagePosts = sort { $frontPageDates{$a} <=> $frontPageDates{$b} } keys(%frontPageDates);
# parse posts in order
my $frontPageContent;
my $fpsize = @frontPagePosts;
print "front page post total $fpsize\n";
foreach my $postfile (@frontPagePosts) {
	print "$postfile\n";
	my $ref = $pageRef{$postfile};
	print "$ref\n";
	my %page = %{ $pages[$ref] };
	foreach my $key (keys %page) { $buffer{$key} = $page{$key}; print "$key $page{$key}\n"; }
	$frontPageContent = $frontPageContent . ParseTemplate('post-template.html');
}
# parse front page
$buffer{'Content'} = $frontPageContent;
open(FILE, ">build/index.html");
print FILE ParseTemplate('template.html');
close(FILE);

# write post inventory
# if (-e 'posts.inventory') { undef("posts.inventory"); }
open(FILE, ">posts.inventory");
foreach my $postfile (keys %checkSums) {
	print FILE "$postfile\n";
	print FILE "$checkSums{$postfile}\n";
	print FILE "$postDates{$postfile}\n";
}
close(FILE);

# write newest post
# if (-e 'posts.newest') { undef("posts.newest"); }
open(FILE, ">posts.newest");
print FILE "$newestPost";
close(FILE);

#
# SUBROUTINES
#

sub GetDateNumber() {
	if ($_[0] ne '') {
		my $parser = DateTime::Format::Natural->new;
	 	my $date_string  = $parser->extract_datetime($_[0]);
	 	my $dt = $parser->parse_datetime($date_string);
		my $datenumber = $dt->year . $dt->month . $dt->day . $dt->hour . $dt->min . $dt->sec;
		return $datenumber;
	} else {
		return 0;
	}
}

# build a post page
sub BuildPostPage() {
	my $postfile = $_[0];
	my $ref = $pageRef{$postfile};
	print "post ref $postfile $ref\n";
	my %page = %{ $pages[$ref] };
	foreach my $key (keys %page) { $buffer{$key} = $page{$key}; }
	$buffer{'Content'} = ParseTemplate('post-template.html');
	open(FILE, ">build/$page{'ShortName'}.html");
	print FILE ParseTemplate('template.html');
	close(FILE);
}

# read a post
sub ReadPost() {
	my $postfile = $_[0];
	if (-e "posts/$postfile") {
		my ($title, $date, $content);
		open(FILE, "posts/$postfile");
		@postlines = <FILE>;
		close(FILE);
		my $l = 0;
		foreach my $line (@postlines) {
			if ($l == 0) {
				$title = $line;
				chomp($title);
				$title =~ s/#//g; #remove header markdown
				$title =~ s/^\s+//; #remove leading spaces
				$title =~ s/\s+$//; #remove trailing spaces
			} elsif ($l == 1) {
				$date = $line;
				chomp($date);
				$date =~ s/#//g; #remove header markdown
				$date =~ s/^\s+//; #remove leading spaces
				$date =~ s/\s+$//; #remove trailing spaces
				# my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($date);
				# $date = "$year$month$day$hh$mm$ss";

			} else {
				$content = $content . $line;
			}
			$l = $l + 1;
		}
		my $m = Text::Markdown->new;
		$content = $m->markdown($content);
		print "$date\n";
		return ($title, $date, $content);
	} else {
		return;
	}
}

# read last newest post
sub GetLastNewestPost() {
	if (-e "posts.newest") {
		open(FILE, "posts.newest");
		my @nplines = <FILE>;
		close(FILE);
		my $postfile = $nplines[0];
		chomp($postfile);
		return $postfile;
	} else {
		return;
	}
}

# parse a template, takes a filename and uses data from %buffer
sub ParseTemplate {
	my @template;
	if (-e $_[0]) {
		my $filename = $_[0];
		if ($buffer{'Dir'} eq "") { $buffer{'Dir'} = "./" }
		open(TEMPLATE, "$filename");
		@template = <TEMPLATE>;
		close(TEMPLATE);
	} else {
		@template[0] = $buffer{$_[0]};
	}
	my $output = '';
	foreach my $line (@template) {
		foreach my $key (keys %buffer) {
			my $search = '{{' . $key . '}}';
			$line =~ s/$search/$buffer{$key}/g;
		}
		$output = $output . $line;
	}
	return $output;
}