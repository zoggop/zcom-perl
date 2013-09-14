# zoggop dot com static website compiler
use File::Copy;
use Date::Parse;
use Text::Markdown 'markdown';
use Date::Calc qw(Delta_Days);

# config variables
my $frontPageDays = 7; # how many days beyond the first post to display on the front page

# read last checksums and dates to compare against
my %lastCheckSums = {};
my %lastDates = {};
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
@postfiles = <DIR>;
closedir(DIR);
my @newPosts;
foreach my $postfile (@postfiles) {
	my $checksum = md5_hex(do { local $/; IO::File->new("posts/$postfile")->getline });
	if ($checksum ne $lastCheckSums{$postfile}) {
		push(@newPosts, $postfile);
	}
}

# create build directory if not existant
unless (-d 'build') { mkdir ('build'); }

# read new posts and create their post pages
my @pages = ();
my %pageRef = {};
my %dates = %lastDates;
my %checkSums = %lastCheckSums;
my $ref = 0;
foreach my $postfile (@newPosts) {
	my $page = {};
	($page->{'Title'}, $page->{'Date'}, $page->{'Content'}) = ReadPost($postfile);
	my $page->{'ShortName'} = $page->{'Title'};
	$page->{'ShortName'} =~ s/ /_/g;
	# $page->{'ShortName'} = $page->{'ShortName'} . $page->{'Date'};
	my $suffix = 1;
	while ($lastCheckSums{"$page->{'ShortName'}.md"}) {
		$page->{'ShortName'} = $page->{'ShortName'} . $suffix;
		$suffix = $suffix + 1;
	}
	move("posts/$postfile", "posts/$page->{'ShortName'}.md");
	$postfile = "$page->{'ShortName'}.md";
	$checkSums{$postfile} = md5_hex(do { local $/; IO::File->new("posts/$postfile")->getline });
	my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($page->{'Date'});
	my $datenumber = "$year$month$day$hh$mm$ss";
	($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($lastDate{$newestPost});
	my $lastdatenumber = "$year$month$day$hh$mm$ss";
	if ($datenumber > $lastdatenumber) {
		$newestPost = $postfile;
	}
	$dates{$postfile} = $page->{'Date'};
	$pages[$ref] = $page;
	$pageRef{$postfile} = $ref;
	BuildPostPage($postfile);
	$ref = $ref + 1;
}

# build index
my %frontPageDates = {};
# find posts within $frontPageDays old
my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($dates{$newestPost});
my @newestYearMonthDay = ($year, $month, $day);
my $newestDateNumber = "$year$month$day$hh$mm$ss";
foreach my $postfile (keys %dates) {
	my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($dates{$postfile});
	my @ymd = ($year, $month, $day);
	print("$postfile\n");
	print("$year $month $day compared to newest $newestYearMonthDay[0] $newestYearMonthDay[1] $newestYearMonthDay[2]\n");
	my $daysold = Delta_Days(@newestYearMonthDay, @ymd);
	if ($daysold <= $frontPageDays) {
		my $datenumber = "$year$month$day$hh$mm$ss";
		$frontPageDates{$postfile} = $datenumber;
	}
}
# sort posts
my @frontPagePosts = sort { $frontPageDates{$a} <=> $frontPageDates{$b} } keys(%frontPageDates);
# parse posts in order
my $frontPageContent;
foreach my $postfile (@frontPagePosts) {
	my $ref = $pageRef{$postfile};
	my %page = %{ $pages[$ref] };
	foreach my $key (keys %page) { $buffer{$key} = $page{$key}; }
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
	print FILE "$dates{$postfile}\n";
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

# build a post page
sub BuildPostPage() {
	my $postfile = $_[0];
	my $ref = $pageRef{$postfile};
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
		}
		$content = markdown($content);
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