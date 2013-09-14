# zoggop dot com static website compiler
use File::Copy;
use Date::Parse;
use Text::Markdown 'markdown';
use Date::Calc qw(Delta_Days);
use IO::File;
use Digest::MD5 qw(md5_hex);
use File::Slurp;
use DateTime::Format::Natural;
use Text::Diff;

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
		} elsif (($a == 1) and (-e "posts/$filename")) {
			$lastCheckSums{$filename} = $line;
			$a = 2;
		} elsif (-e "posts/$filename") {
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
		my $checksum = md5_hex(read_file("posts/$postfile"));
		if ($checksum ne $lastCheckSums{$postfile}) {
			push(@newPosts, $postfile);
		}
		if ($newestPost eq '') { $newestPost = $postfile; }
	}
}
my $totalNewPosts = @newPosts;
print "total new posts: $totalNewPosts\n";
if ($totalNewPosts == 0) { exit; }

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
	my ($title, $date, $content) = ReadPost($postfile);
	my $shortname = TitleToShortName($title);
	# assign new filename and deal with duplicates
	if ($postfile ne "$shortname.md") {
		print "file $postfile is not $shortname.md\n";
		if (-e "posts/$shortname.md") {
			print "file $shortname.md already exists\n";
			# determine if duplicate is an update or just has the same title
			my ($dtitle, $ddate, $dcontent) = ReadPost("$shortname.md");
			if ($dtitle ne $title) {
				print "duplicate file title $dtitle doesn't match title $title\n";
				# move duplicate file with title that doesn't match filename
				for ($i = 0; $i <= $#newPosts; $i++) {
					if ($newPosts[i] eq "$shortname.md") {
						my $dshortname = TitleToShortName($dtitle);
						my $suffix = 1;
						while (-e "posts/$dshortname.md") {
							$dshortname = $dshortname . $suffix;
							$suffix = $suffix + 1;
						}
						move("posts/$newPosts[i]", "posts/$dshortname.md");
						$newPosts[i] = "$dshortname.md";
					}
				}
			} elsif ($lastCheckSums{"$shortname.md"}) {
				print "$shortname.md exists in last inventory\n";
				my $diff = diff \$content, \$dcontent;
				if (length($diff) < length($content) / 2) {
					print "diff is more than half match, moving old to backup\n";
					# move duplicate to backup
					delete $lastCheckSums{"$shortname.md"};
					unless (-d "backup") { mkdir "backup"; }
					my $suffix = 1;
					my $backupname = $shortname;
					while (-e "backup/$backupname.md") {
						$backupname = $backupname . $suffix;
						$suffix = $suffix + 1;
					}
					move("posts/$shortname.md", "backup/$backupname.md")
				} else {
					print "diff is less than half match, finding new filename\n";
					# find new filename
					my $suffix = 1;
					while (-e "posts/$shortname.md") {
						$shortname = $shortname . $suffix;
						$suffix = $suffix + 1;
					}
				}
			}
		}
		print "moving $postfile to $shortname.md\n";
		move("posts/$postfile", "posts/$shortname.md");
		$postfile = "$shortname.md";
	}
	$checkSums{"$postfile"} = md5_hex(read_file("posts/$postfile"));
#	my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($date);
#	($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($lastDate{$newestPost});
	if (GetDateNumber($date) > GetDateNumber($lastDate{$newestPost})) {
		$newestPost = $postfile;
	}
	$postDates{"$postfile"} = $date;
	my $page = {};
	$page->{'Title'} = $title;
	$page->{'Date'} = $date;
	$page->{'Content'} = $content;
	$page->{'ShortName'} = $shortname;
	$pages[$ref] = $page;
	$pageRef{$postfile} = $ref;
	BuildPostPage($postfile);
	$ref = $ref + 1;
}

# build index
my %frontPageDates;
# find posts within $frontPageDays old
print "newest $newestPost $postDates{$newestPost}\n";
my @newestYearMonthDay = GetYearMonthDay($postDates{$newestPost});
my $newestDateNumber = GetDateNumber($postDates{$newestPost});
foreach my $postfile (keys %checkSums) {
#	my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($dates{$postfile});
	print "$postfile $postDates{$postfile}\n";
	my @ymd = GetYearMonthDay($postDates{$postfile});
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
my @frontPagePosts = sort { $frontPageDates{$b} <=> $frontPageDates{$a} } keys(%frontPageDates);
# parse posts in order
my $frontPageContent;
my $fpsize = @frontPagePosts;
print "front page post total $fpsize\n";
foreach my $postfile (@frontPagePosts) {
	print "$postfile\n";
	my $ref = $pageRef{$postfile};
	print "$ref\n";
	if ($ref) {
		my %page = %{ $pages[$ref] };
		foreach my $key (keys %page) { $buffer{$key} = $page{$key}; print "$key $page{$key}\n"; }
	} else {
		($buffer{'Title'}, $buffer{'Date'}, $buffer{'Content'}) = ReadPost($postfile);
		$buffer{'ShortName'} = $postfile;
		$buffer{'ShortName'} =~ s{\.[^.]+$}{}; # removes extension
	}
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

sub TitleToShortName() {
	my $shortname= lc($_[0]);
	$shortname =~ s/ /_/g;
	return $shortname;
}

sub GetYearMonthDay() {
	if ($_[0] ne '') {
		my $parser = DateTime::Format::Natural->new;
	 	my $date_string  = $parser->extract_datetime($_[0]);
	 	my $dt = $parser->parse_datetime($date_string);
		return ($dt->year, $dt->month, $dt->day);
	} else {
		return (0, 0, 0);
	}
}

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