#!/usr/bin/perl

# zoggop dot com static website compiler
use File::Copy;
use Time::HiRes qw(time);
use File::Copy::Recursive qw(dircopy);
use Text::Markdown 'markdown';
use Date::Calc qw(Delta_Days);
use IO::File;
use Digest::MD5 qw(md5_hex);
use DateTime::Format::Natural;
use Text::Diff;
use Image::Magick;
use String::Compare;

my $DebugMode = 0;

# image extensions
my %imageExts = qw(PDF 1 JPG 1 PNG 1 SVG 1 JNG 1 GIF 1);

# month names
my %num2mon = qw(
	1 January 2 February 3 March 4 April 5 May 6 June 7 July 8 August 9 September 10 October 11 November 12 December
);

# config variables
my $frontPageDays = 7; # how many days beyond the first post to display on the front page
my $headlineArchiveDays = 30;
my $FinalImageExt = "jpg";
my $FinalImageQuality = 90;
my $BackgroundImageQuality = 75;
my $LargeWidth = 800;
my $LargeHeight = 680;
my $ThumbWidth = 300;
my $ThumbHeight = 680;
my $BackgroundWidth = 1920;
my $BackgroundHeight = 1080;
my $PdfDensity = 100;

# geometry strings for passing to imagemagick
my $LargeSize = $LargeWidth . 'x' . $LargeHeight;
my $ThumbSize = $ThumbWidth . 'x' . $ThumbHeight;
my $BackgroundSize = $BackgroundWidth . 'x' . $BackgroundHeight;

my $background;

# command line arguments
my %CLARG = {};
foreach my $arg (@ARGV) {
	$CLARG{$arg} = 1;
}

if ($CLARG{'all'}) {
	if (-e "posts.inventory") { unlink "posts.inventory"; }
	if (-e "posts.newest") { unlink "posts.newest"; }
}

if ($CLARG{'debug'}) { $DebugMode = 1; }

# copy additives
# my $dirsync = new File::DirSync {
# 	verbose => 1,
# 	nocache => 0,
# 	localmode => 0,
# };
# $dirsync->src("additives");
# $dirsync->dst("build");
# $dirsync->rebuild();
# $dirsync->dirsync();

my $start_run = time();

# my ($num_of_files_and_dirs,$num_of_dirs,$depth_traversed) = 
# print "$num_of_files_and_dirs items copied from additives/ to build/ -- $num_of_dirs directories, $depth_traversed deep\n";
# SyncDirectory("additives", "build");

# create build directory if not existant
unless (-d 'build') { mkdir ('build'); }

if (uc($^O) eq 'LINUX') {
	system('rsync -rpogt additives/ build/');
} else {
	dircopy('additives','build') or die $!;
}

print ("\nadditive to build sync took " . (time() - $start_run) . " seconds\n\n");

my $untitled = 0;

# read last checksums and dates to compare against
my @deletedPosts;
my %lastAssetInvStr;
my %lastCheckSums;
my %datenumbers;
my %years;
my %months;
my %days;
if (-e "posts.inventory") {
	open(FILE, "posts.inventory");
	@cslines = <FILE>;
	close(FILE);
	my $f = 0;
	my $filename;
	my $checksum;
	my $exists = 0;
	foreach my $line (@cslines) {
		chomp($line);
		if ($f == 0) {
			$filename = $line;
			if (-e "posts/$filename") {
				$exists = 1;
			} else {
				$exsts = 0;
				push(@deletedPosts, $filename)
			}
		} else {
			if ($exists == 1) {
				if ($f == 1) {
					$lastCheckSums{$filename} = $line;
				} elsif ($f == 2) {
					$datenumbers{$filename} = $line;
				} elsif ($f == 3) {
					($years{$filename}, $months{$filename}, $days{$filename}) = split(/ /, $line);
				} elsif ($f == 4) {
					$lastAssetInvStr{$filename} = $line;
				}
			}
		}
		$f = $f + 1;
		if ($f == 5) { $f = 0; }
	}
}

# ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

# get last year info
my %allYears;
open(FILE, "years.list");
my @yearlines = <FILE>;
close(FILE);
foreach my $line (@yearlines) {
	chomp($line);
	(my $year, my $numposts) = split(/ /, $line);
	$allYears{$year} = $numposts;
}

# get last newest post info
my $newestPost = GetLastNewestPost();
my $newestDateNumber = $datenumbers{$newestPost};

# read post markdown checksums to find new posts
opendir(DIR, "posts");
@postfiles = readdir(DIR);
closedir(DIR);
my @newPosts;
my %assetInvStr;
foreach my $postfile (@postfiles) {
	# checks if it's a directory just because this would cause it to fail, not because this is a likely scenario
	unless (-d "posts/$postfile") {
		my $checksum = GetChecksum("posts/$postfile");
		$assetInvStr{$postfile} = GetAssetInventoryString($postfile);
		if ($checksum ne $lastCheckSums{$postfile}) {
			push(@newPosts, $postfile);
		} else {
			# check the post's assets for changes if it has any
			DebugPrint("$assetInvStr{$postfile} compared to $lastAssetInvStr{$postfile}\n");
			if ($assetInvStr{$postfile} ne $lastAssetInvStr{$postfile}) {
				push(@newPosts, $postfile)
			}
		}
	}
}
my $totalNewPosts = @newPosts;
print "total new posts: $totalNewPosts\n";
if (($totalNewPosts == 0) and not ($CLARG{'index'})) { exit; }

# getting the current date
my $dtnow = DateTime->now;

# setting buffers
$buffer{'Subtitle'} = "";
$buffer{'ThisYear'} = $dtnow->year;

# read new posts and create their post pages
my %yearArchiveUpdate;
my %monthArchiveUpdate;
my @posts;
my %postRef;
my %checkSums;
foreach my $key (keys %lastCheckSums) { $checkSums{$key} = $lastCheckSums{$key}; }
my $ref = 0;
foreach my $postfile (@newPosts) {
	my ($title, $date, $content) = ReadPost($postfile);
	my $shortname = TitleToShortName($title);
	print("NEW: $postfile \"$title\" ");
	# assign new filename and deal with duplicates
	my $foundduplicate = 0;
	if ($postfile ne "$shortname.md") {
		DebugPrint("file $postfile is not $shortname.md\n");
		if (-e "posts/$shortname.md") {
			DebugPrint("file $shortname.md already exists\n");
			# determine if duplicate is an update or just has the same title
			my ($dtitle, $ddate, $dcontent) = ReadPost("$shortname.md");
			if ($dtitle ne $title) {
				print "duplicate filename ";
				DebugPrint("\nduplicate file title $dtitle doesn't match title $title\n");
				# move duplicate file with title that doesn't match filename
				for ($i = 0; $i <= $#newPosts; $i++) {
					if ($newPosts[i] eq "$shortname.md") {
						my $dshortname = NonDuplicateSuffix(TitleToShortName($dtitle), 'posts/', '.md');
						move("posts/$newPosts[i]", "posts/$dshortname.md");
						$newPosts[i] = "$dshortname.md";
					}
				}
			} elsif ($lastCheckSums{"$shortname.md"}) {
				DebugPrint("$shortname.md exists in last inventory\n");
				my ($dtitle, $ddate, $dcontent) = ReadPost("$shortname.md");
				my $compare = compare($content, $dcontent);
				DebugPrint("$shortname.md is $compare alike to $postfile\n");
				if ($compare > 0.4) {
					print "update ";
					DebugPrint("comparison is match, moving old to backup\n");
					# move duplicate to backup
					delete $lastCheckSums{"$shortname.md"};
					delete $checkSums{"$shortname.md"};
					unless (-d "backup") { mkdir "backup"; }
					my $backupname = NonDuplicateSuffix($shortname, 'backup/', '.md');
					move("posts/$shortname.md", "backup/$backupname.md");
					$foundduplicate = 1;
				} else {
					print "duplicate ";
					DebugPrint("diff is less than half match, finding new filename\n");
					# find new filename
					my $shortname = NonDuplicateSuffix($shortname, 'posts/', '.md');
				}
			}
		} else {
			if ($lastCheckSums{$postfile}) {
				delete $lastCheckSums{$postfile};
				delete $checkSums{$postfile};
			}
		}
		print " -- renaming to $shortname.md";
		move("posts/$postfile", "posts/$shortname.md");
		# move asset directory too
		my $postbase = $postfile;
		$postbase =~ s/.md//;
		if (-d "posts/$postbase") {
			move("posts/$postbase", "posts/$shortname");
		}
		$postfile = "$shortname.md";
	}

	# look for dupicates by a different title
	# DebugPrint($foundduplicate);
	# if ($foundduplicate == 0) {
	# 	my $count = 0;
	# 	foreach my $dup (sort {$datenumbers{$b} cmp $datenumbers{$a}} keys %lastCheckSums) {
	# 		my ($dtitle, $ddate, $dcontent) = ReadPost($dup);
	# 		my $compare = compare($content, $dcontent);
	# 		DebugPrint("$dup is $compare alike to $postfile\n");
	# 		if ($compare > 0.4) {
	# 			print " is an update of $dup ";
	# 			DebugPrint("comparison is match, moving old to backup\n");
	# 			# move duplicate to backup
	# 			delete $lastCheckSums{$dup};
	# 			delete $checkSums{$dup};
	# 			unless (-d "backup") { mkdir "backup"; }
	# 			my $backupname = NonDuplicateSuffix(ShortName($dtitle), 'backup/', '.md');
	# 			move("posts/$dup", "backup/$backupname.md");
	# 			last;
	# 		}
	# 		$count = $count + 1;
	# 		if ($count == 3) { last; }
	# 	}
	# }

	print "\n";
	$checkSums{$postfile} = GetChecksum("posts/$postfile");
	$datenumbers{$postfile} = GetDateNumber($date);
	DebugPrint("$datenumbers{$postfile} compared to $newestDateNumber\n");
	if ($datenumbers{$postfile} > $newestDateNumber) {
		$newestPost = $postfile;
		$newestDateNumber = $datenumbers{$postfile};
	}
	($years{$postfile}, $months{$postfile}, $days{$postfile}) = GetYearMonthDay($date);

	# add to complete list of years for the list of archive pages
	if ($allYears{$years{$postfile}}) {
		$allYears{$years{$postfile}} = $allYears{$years{$postfile}} + 1;
	} else {
		$allYears{$years{$postfile}} = 1;
	}

	# set year and month archives that need to be updated
	$yearArchiveUpdate{$years{$postfile}} = 1;
	$monthArchiveUpdate{"$years{$postfile} $months{$postfile}"} = 1;

	# store post data
	my $post = {};
	$post->{'Date'} = ReformatDate($date);
	$post->{'Title'} = $title;
	$post->{'Content'} = $content;
	$post->{'ShortName'} = $shortname;
	$post->{'Assets'} = BuildPostAssets($shortname);
	$posts[$ref] = $post;
	$postRef{$postfile} = $ref;
	BuildPostPage($postfile);
	$ref = $ref + 1;
}

# find post ages and put into archives that need to be updated
my %frontPageDates;
my %headlineArchiveDates;
my %yearArchives;
my %monthArchives;
print "NEWEST: $newestPost\n";
my @newestYearMonthDay = ($years{$newestPost}, $months{$newestPost}, $days{$newestPost});
foreach my $postfile (keys %checkSums) {
	my @ymd = ($years{$postfile}, $months{$postfile}, $days{$postfile});

	# add to list of pages within each year and month's archive if it falls within year or month archive to be updated
	if ($yearArchiveUpdate{$ymd[0]}) {
		$yearArchives{$years{$postfile}}{$postfile} = $datenumbers{$postfile};
	}
	if ($monthArchiveUpdate{"$ymd[0] $ymd[1]"}) {
		$monthArchives{"$years{$postfile} $months{$postfile}"}{$postfile} = $datenumbers{$postfile};
	}

	# only consider those within the last two months
	my $consider = 0;
	if ($CLARG{'all'}) {
		$consider = 1;
	} else {
		if ($ymd[0] == $newestYearMonthDay[0]) {
			if ($ymd[1] >= $newestYearMonthDay[1] - 2) {
				$consider = 1;
			}
		} elsif (($ymd[0] == $newestYearMonthDay[0] - 1) and ($newestYearMonthDay[1] <= 2)) {
			if ($ymd[1] >= 10 ) {
				$consider = 1;
			}
		}
	}
	if ($consider == 1) {
		DebugPrint("$ymd[0] $ymd[1] $ymd[2] compared to newest $newestYearMonthDay[0] $newestYearMonthDay[1] $newestYearMonthDay[2]\n");
		my $daysold = abs Delta_Days(@newestYearMonthDay, @ymd);
		DebugPrint("$postfile is $daysold days old\n");
		if ($daysold <= $frontPageDays) {
			print "$postfile made front page\n";
			$frontPageDates{$postfile} = $datenumbers{$postfile};
		} elsif ($daysold <= $headlineArchiveDays) {
			print "$postfile made headline archive\n";
			$headlineArchiveDates{$postfile} = $datenumbers{$postfile};
		}
	}
}

# sort {$hash{$b} cmp $hash{$a}} keys %hash

# sort front page posts
my @frontPagePosts = sort { $frontPageDates{$b} <=> $frontPageDates{$a} } keys(%frontPageDates);
push(@frontPagePosts, 'post-template.html');
my $frontPageContent = BuildPostList(@frontPagePosts);
# sort headline archive posts
my @headlineArchivePosts = sort { $headlineArchiveDates{$b} <=> $headlineArchiveDates{$a} } keys(%headlineArchiveDates);
push(@headlineArchivePosts, 'post-headline-template.html');
my $headlineArchiveContent = BuildPostList(@headlineArchivePosts);
# sort year list
my @yearList = reverse sort keys %allYears;
my $yearListContent;
foreach my $year (@yearList) {
	$buffer{'Year'} = $year;
	$buffer{'Number'} = $allYears{$year};
	$yearListContent = $yearListContent . ParseTemplate('year-template.html');
}
# build index
$buffer{'FrontPage'} = $frontPageContent;
$buffer{'HeadlineArchive'} = $headlineArchiveContent;
$buffer{'YearList'} = $yearListContent;
$buffer{'Content'} = ParseTemplate('index-template.html');
$buffer{'Title'} = "";
# $buffer{'Subtitle'} = "<p>\"I never see him. I looked at him twice or thrice about a year ago, before he recognised me, and then I shut my eyes; and if he were to cross their balls twelve times between each day's sunset and sunrise, except from memory, I should hardly know what shape had gone by.\"</p><p>\"Lucy, what do you mean?\" said she, under her breath.</p><p>\"I mean that I value vision, and dread being struck stone blind.\"</p>";
open(FILE, ">build/index.html");
print FILE ParseTemplate('template.html');
close(FILE);

# sort archives and build archive pages
foreach my $year (keys %yearArchives) {
	my @yearPosts = sort { $yearArchives{$year}{$b} <=> $yearArchives{$year}{$a} } keys($yearArchives{$year});
	push(@yearPosts, 'post-headline-template.html');
	$buffer{'Content'} = BuildPostList(@yearPosts);
	$buffer{'Title'} = $year;
	open(FILE, ">build/$year.html");
	print FILE ParseTemplate('template.html');
	close(FILE);
}
foreach my $yearmonth (keys %monthArchives) {
	my @monthPosts = sort { $monthArchives{$yearmonth}{$b} <=> $monthArchives{$yearmonth}{$a} } keys($monthArchives{$yearmonth});
	push(@monthPosts, 'post-template.html');
	$buffer{'Content'} = BuildPostList(@monthPosts);
	my ($year, $month) = split(/ /, $yearmonth);
	$buffer{'Title'} = "$num2mon{$month} $year";
	open(FILE, ">build/$year-$month.html");
	print FILE ParseTemplate('template.html');
	close(FILE);
}

# write post inventory
open(FILE, ">posts.inventory");
foreach my $postfile (keys %checkSums) {
	print FILE "$postfile\n";
	print FILE "$checkSums{$postfile}\n";
	print FILE "$datenumbers{$postfile}\n";
	print FILE "$years{$postfile} $months{$postfile} $days{$postfile}\n";
	print FILE "$assetInvStr{$postfile}\n";
}
close(FILE);

# write newest post
open(FILE, ">posts.newest");
print FILE "$newestPost";
close(FILE);

# write year list
open(FILE, ">years.list");
foreach my $year (sort keys %allYears) {
	print FILE "$year $allYears{$year}\n";
}
close(FILE);

print "\ncompiled in " . (time() - $start_run) . " seconds\n";


###############
# SUBROUTINES #
###############

sub BuildPostList() {
	# parse front page posts in order
	my $postlist;
	my $template = pop(@_);
	my $fpsize = @_;
	# print "post total $fpsize with template $template\n";
	foreach my $postfile (@_) {
		$buffer{'Assets'} = '';
		my $ref = $postRef{$postfile};
		if ($ref) {
			my %post = %{ $posts[$ref] };
			foreach my $key (keys %post) { $buffer{$key} = $post{$key}; }
		} else {
			($buffer{'Title'}, $buffer{'Date'}, $buffer{'Content'}) = ReadPost($postfile);
			$buffer{'Date'} = ReformatDate($buffer{'Date'});
			$buffer{'ShortName'} = $postfile;
			$buffer{'ShortName'} =~ s{\.[^.]+$}{}; # removes extension
			$buffer{'Assets'} = BuildPostAssets($buffer{'ShortName'});
		}
		$postlist = $postlist . ParseTemplate($template);
	}
	return $postlist;
}

sub GetAssetInventoryString() {
	my $postfile = $_[0];
	(my $post, my $ext) = GetBaseExt($postfile);
	unless (-d "posts/$post") { return ""; }
	opendir(DIR, "posts/$post");
	my @assets = readdir(DIR);
	closedir(DIR);
	my $assetInventoryString = "";
	foreach my $asset (@assets) {
		unless ((-d "posts/$post/$asset") or ($asset eq 'Thumbs.db')) {
			$assetInventoryString = $assetInventoryString . "//" . $asset . "|" . (stat("posts/$post/$asset"))[9];
		}
	}
	return $assetInventoryString;
}

sub BuildPostAssets() {
	my $post = $_[0];
	unless (-d "posts/$post") { return ""; }
	opendir(DIR, "posts/$post");
	my @assets = readdir(DIR);
	closedir(DIR);
	my %captions;
	my %aorder;
	my $n = 1;
	if (-e "posts/$post/assets.captions") {
		# read captions if existant
		open(FILE, "posts/$post/assets.captions");
		my @caplines = <FILE>;
		close(FILE);
		my $ac = 0;
		my $a;
		foreach my $line (@caplines) {
			chomp($line);
			if ($ac == 0) {
				$a = $line;
				$ac = 1;
			} else {
				$captions{$a} = markdown($line);
				$aorder{$a} = $n;
				$n = $n + 1;
				$ac = 0;
			}
		}
	}
	my %ahtml;
	print "assets: ";
	foreach my $asset (@assets) {
		unless ((-d "posts/$post/$asset") or ($asset eq 'assets.captions') or ($asset eq 'Thumbs.db')) {
			# read asset
			(my $base, my $ext) = GetBaseExt($asset);
			my $assethtml;
			$ext = uc($ext);
			print "$base $ext, ";
			$buffer{'Caption'} = $captions{$asset};
			if ($imageExts{$ext}) {
				($buffer{'Thumb'}, $buffer{'Image'}) = Thumbnail($asset, $post);
				$assethtml = ParseTemplate('asset-image-template.html');
			} else {
				copy("posts/$post/$asset", "build/$post/$asset") or die "Copy failed: $!";
				$buffer{'File'} = "$post/$asset";
				$buffer{'Filename'} = $asset;
				$assethtml = ParseTemplate('asset-file-template.html');
			}
			$ahtml{$asset} = $assethtml;
			unless ($aorder{$asset}) {
				$aorder{$asset} = $n;
				$n = $n + 1;
			}
		}
	}
	print "\n";
	@assets = sort { $aorder{$a} <=> $aorder{$b} } keys(%ahtml);
	my $assetshtml;
	foreach $asset (@assets) {
		$assetshtml = $assetshtml . $ahtml{$asset};
	}
	return $assetshtml, $assetInventoryString;
}

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


sub ReformatDate() {
	my ($year, $month, $day);
	($year, $month, $day) = GetYearMonthDay($_[0]);
	$buffer{'Year'} = $year;
	$buffer{'Month'} = $month;
	$buffer{'MonthName'} = $num2mon{$month};
	$buffer{'Day'} = $day;
	return ParseTemplate('date-template.html');
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
		my $datenumber = $dt->year . sprintf("%003d", $dt->doy) . sprintf("%02d", $dt->hour) . sprintf("%02d", $dt->min);
		DebugPrint("$datenumber\n");
		return $datenumber;
	} else {
		return 0;
	}
}

# build a post page
sub BuildPostPage() {
	my $postfile = $_[0];
	my $ref = $postRef{$postfile};
	DebugPrint("post ref $postfile $ref\n");
	my %post = %{ $posts[$ref] };
	foreach my $key (keys %post) { $buffer{$key} = $post{$key}; }
	$buffer{'Content'} = ParseTemplate('post-template.html');
	$buffer{'Title'} = '';
	open(FILE, ">build/$post{'ShortName'}.html");
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
			} else {
				$content = $content . $line;
			}
			$l = $l + 1;
		}
		my $m = Text::Markdown->new;
		$content = $m->markdown($content);
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

# creates a thumbnail from an image in the source directory. also creates a midsize, and copies the source image to the build directory with a new name
sub Thumbnail {
	my $image = $_[0];
	(my $base, my $ext) = GetBaseExt($image);
	my $post = $_[1];
	# create image dir in build/ if necessary
	unless (-d "build/$post") {
		mkdir ("build/$post");
	}
	my $FullSizeURL;
	#localize imagemagick and warning vars
	my $IM = "";
	my $x;
	if ("\U$ext" eq "PDF") {
		unless ((-e "build/$post/$image") and not ($CLARG{'overwrite'})) {
			$IM = ReadPDF("posts/$post/$image");
			copy("posts/$post/$image", "build/$post/$image") or die "Copy failed: $!";
		}
		$FullSizeURL = "$post/$image";
	} else {
		# read source image
		$IM = Image::Magick->new;
		$x = $IM->Read("posts/$post/$image");
		if ($x) {
			print $x, "\n";
		} else {
			# get width and height
			(my $width, my $height) = $IM->Get('height', 'width');
			if (($width <= $LargeWidth) and ($height <= $LargeHeight)) {
				unless ((-e "build/$post/$image") and not ($CLARG{'overwrite'})) {
					copy("posts/$post/$image", "build/$post/$image") or die "Copy failed: $!";
				}
					$FullSizeURL = "$post/$image";
			} else {
				unless ((-e "build/$post/$base.$FinalImageExt") and not ($CLARG{'overwrite'})) {
					ResizeImage($IM, $LargeSize, "build/$post/$base");
				}
				$FullSizeURL = "$post/$base.$FinalImageExt";
			}
			# unless ($background) {
			# 	if (($width >= $BackgroundWidth / 2) and ($height >= BackgroundHeight / 2)) {
			# 		BackgroundifyImage($IM);
			# 		$background = 1;
			# 	}
			# }
		}
	}
	unless ($x) {
		# resize and write thumb image
		unless ((-e "build/$post/$base-thumb.$FinalImageExt") and not ($CLARG{'overwrite'})) {
			ResizeImage($IM, $ThumbSize, "build/$post/$base-thumb");
		}
		DebugPrint("$_[0] --> $post/$base\n");
		return ("$post/$base-thumb.$FinalImageExt", $FullSizeURL);
	}
}

# read source pdf and trim edges
sub ReadPDF {
	my $PDF = Image::Magick->new;
	$PDF->Set(density=>$PdfDensity);
	$PDF->Set(units=>"PixelsPerInch");
	my $x = $PDF->Read($_[0] . '[0]');
	warn "$x" if "$x";
	$PDF->Set(alpha=>"Off");
	$x = $PDF->Trim();
	warn "$x" if "$x";
	return $PDF;
}

# resize a magick image
sub ResizeImage {
	my $image = $_[0]->Clone();
	my $size = $_[1];
	my $base = $_[2];
	my $x = $image->Resize(geometry=>"$size");
	warn "$x" if "$x";
	$x = $image->Set(quality=>"$FinalImageQuality");
	warn "$x" if "$x";
	$x = $image->Write("$base.$FinalImageExt");
	warn "$x" if "$x";
	undef $image;
}

# turn an image into a background
sub BackgroundifyImage {
	my $image = $_[0]->Clone();
	my $x = $image->Resize(geometry=>"$BackgroundSize");
	warn "$x" if "$x";
	# $x = $image->Colorize(fill=>"white", blend=>"0.1");
	# warn "$x" if "$x";
	$x = $image->Set(quality=>"$BackgroundImageQuality");
	warn "$x" if "$x";
	$x = $image->Write("build/bg.$FinalImageExt");
	warn "$x" if "$x";
	undef $image;
}

sub GetBaseExt() {
	my $file = $_[0];
	my @dot = split(/\./, $file);
	my $ext = pop(@dot);
	my $base = join('', @dot);
	return ($base, $ext);
}

sub SyncDirectory() {
	print "syncing $_[0] to $_[1]\n";
	unless (-d $_[1]) { mkdir($_[1]); }
	opendir(DIR, $_[0]);
	@dir = readdir(DIR);
	closedir(DIR);
	foreach my $item (@dir) {
		if (("$item" ne '.') and ("$item" ne '..')) {
			print "$_[0]/$item ";
			if (-d "$_[0]/$item") {
				SyncDirectory("$_[0]/$item", "$_[1]/$item");
			} else {
				if (-f "$_[1]/$item") {
					if (GetChecksum("$_[0]/$item") != GetChecksum("$_[1]/$item")) {
						print "md5 differs ";
						copy("$_[0]/$item", "$_[1]/$item") or die "Copy failed: $!";
					} else {
						print "md5 same ";
					}
				} else { 
					print "target file $_[1]/$item doesn't exist ";
					copy("$_[0]/$item", "$_[1]/$item") or die "Copy failed: $!";
				}
			}
			print "\n";
		}
	}
}

sub GetChecksum() {
	open (CHECK, $_[0]) or die "Can't open '$_[0]': $!";
	binmode (CHECK);
	my $checksum = Digest::MD5->new->addfile(CHECK)->hexdigest;
	close(CHECK);
	return $checksum;
}

sub NonDuplicateSuffix() {
	my $string = $_[0];
	my $base = $_[0];
	my $suffix = 1;
	while (-e "$_[1]$string$_[2]") {
		$string = $base . $suffix;
		$suffix = $suffix + 1;
	}
	return $string;
}

sub DebugPrint() {
	if ($DebugMode) { print $_[0]; }
}