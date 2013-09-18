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
use Image::Magick;

# image extensions
my @iexts = (
	'PDF',
	'JPG',
	'JPEG',
	'PNG',
	'SVG',
	'JNG',
	'GIF'
);

my %imageExts;
foreach my $ext (@iexts) {
	$imageExts{$ext} = 1;
}

# month names
my %num2mon = qw(
	1 January 2 February 3 March 4 April 5 May 6 June 7 July 8 August 9 September 10 October 11 November 12 December
);

# config variables
my $frontPageDays = 7; # how many days beyond the first post to display on the front page
my $headlineArchiveDays = 30;
my $FinalImageExt = "jpg";
my $FinalImageQuality = 90;
my $LargeWidth = 800;
my $LargeHeight = 680;
my $ThumbWidth = 300;
my $ThumbHeight = 680;
my $PdfDensity = 100;

# geometry strings for passing to imagemagick
my $LargeSize = $LargeWidth . 'x' . $LargeHeight;
my $ThumbSize = $ThumbWidth . 'x' . $ThumbHeight;

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
my $newestDateNumber = 0;

# read post markdown checksums to find new posts
opendir(DIR, "posts");
@postfiles = readdir(DIR);
closedir(DIR);
my @newPosts;
foreach my $postfile (@postfiles) {
	unless (-d "posts/$postfile") {
		my $checksum = md5_hex(read_file("posts/$postfile"));
		if ($checksum ne $lastCheckSums{$postfile}) {
			push(@newPosts, $postfile);
		}
	}
}
my $totalNewPosts = @newPosts;
print "total new posts: $totalNewPosts\n";
if ($totalNewPosts == 0) { exit; }

# create build directory if not existant
unless (-d 'build') { mkdir ('build'); }

# read new posts and create their post pages
my %updateYearArchive;
my %updateMonthArchive;
my @posts;
my %postRef;
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
		# move asset directory too
		my $postbase = $postfile;
		$postbase =~ s/.md//;
		if (-d "posts/$posebase") {
			move("posts/$postbase", "posts/$shortname");
		}
		$postfile = "$shortname.md";
	}
	$checkSums{"$postfile"} = md5_hex(read_file("posts/$postfile"));
	if (GetDateNumber($date) > $newestDateNumber) {
		$newestPost = $postfile;
		$newestDateNumber = GetDateNumber($date);
	}
	$postDates{"$postfile"} = $date;
	# find which archive pages need to be updated
	my ($year, $month, $day) = GetYearMonthDay($date);
	$updateYearArchive{$year} = 1;
	$updateMonthArchive{"$year $month"} = 1;
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
my %allYears;
my %yearArchives;
my %monthArchives;
print "newest $newestPost $postDates{$newestPost}\n";
my @newestYearMonthDay = GetYearMonthDay($postDates{$newestPost});
foreach my $postfile (keys %checkSums) {
#	my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($dates{$postfile});
	print "$postfile $postDates{$postfile}\n";
	my @ymd = GetYearMonthDay($postDates{$postfile});
	print("$ymd[0] $ymd[1] $ymd[2] compared to newest $newestYearMonthDay[0] $newestYearMonthDay[1] $newestYearMonthDay[2]\n");
	my $daysold = abs Delta_Days(@newestYearMonthDay, @ymd);
	print ("days old $daysold\n");
	if ($daysold <= $frontPageDays) {
		print "$postfile made front page\n";
		$frontPageDates{$postfile} = $daysold;
	} elsif ($daysold <= $headlineArchiveDays) {
		print "$postfile made headline archive\n";
		$headlineArchiveDates{$postfile} = $daysold;
	}
	my $year = $ymd[0];
	my $month = $ymd[1];
	my $day = $ymd[2];
	# add to complete list of years for the list of archive pages
	if ($allYears{$year}) {
		$allYears{$year} = $allYears{$year} + 1;
	} else {
		$allYears{$year} = 1;
	}
	# compile list of pages within each year and month's archive
	if ($updateYearArchive{$year}) {
		my $order = Delta_Days(($year, 1, 1), @ymd);
		$yearArchives{$year}{$postfile} = $order;
	}
	if ($updateMonthArchive{"$year $month"}) {
		my $order = Delta_Days(($year, $month, 1), @ymd);
		$monthArchives{"$year $month"}{$postfile} = $order;
	}
}

# sort {$hash{$b} cmp $hash{$a}} keys %hash

# sort front page posts
my @frontPagePosts = sort { $frontPageDates{$a} <=> $frontPageDates{$b} } keys(%frontPageDates);
push(@frontPagePosts, 'post-template.html');
my $frontPageContent = BuildPostList(@frontPagePosts);
# sort headline archive posts
my @headlineArchivePosts = sort { $headlineArchiveDates{$a} <=> $headlineArchiveDates{$b} } keys(%headlineArchiveDates);
push(@headlineArchivePosts, 'post-headline-template.html');
my $headlineArchiveContent = BuildPostList(@headlineArchivePosts);
# sort year list
my @yearList = sort keys %allYears;
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
$buffer{'Title'} = '';
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

sub BuildPostList() {
	# parse front page posts in order
	my $postlist;
	my $template = pop(@_);
	my $fpsize = @_;
	print "post total $fpsize with template $template\n";
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

sub BuildPostAssets() {
	my $post = $_[0];
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
	foreach my $asset (@assets) {
		unless ((-d "posts/$post/$asset") or ($asset eq 'assets.captions')) {
			# read asset
			(my $base, my $ext) = GetBaseExt($asset);
			my $assethtml;
			$ext = uc($ext);
			print "$base $ext $imageExts{$ext}\n";
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
	@assets = sort { $aorder{$a} <=> $aorder{$b} } keys(%ahtml);
	my $assetshtml;
	foreach $asset (@assets) {
		$assetshtml = $assetshtml . $ahtml{$asset};
	}
	return $assetshtml;
}

sub TitleToShortName() {
	my $shortname= lc($_[0]);
	$shortname =~ s/[^a-z0-9]/_/g;
	return $shortname;
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
		print $datenumber, "\n";
		return $datenumber;
	} else {
		return 0;
	}
}

# build a post page
sub BuildPostPage() {
	my $postfile = $_[0];
	my $ref = $postRef{$postfile};
	print "post ref $postfile $ref\n";
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
		$IM = ReadPDF("posts/$post/$image");
		copy("posts/$post/$image", "build/$post/$image") or die "Copy failed: $!";
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
			if (($width <= $LargeWidth) and ($height <= $LargeHeight) and ($ext eq $FinalImageExt)) {
				copy("posts/$post/$image", "build/$post/$image") or die "Copy failed: $!";
			} else {
				ResizeImage($IM, $LargeSize, "build/$post/$base");
			}
			$FullSizeURL = "$post/$base.$FinalImageExt";
		}
	}
	unless ($x) {
		# resize and write thumb image
		ResizeImage($IM, $ThumbSize, "build/$post/$base-thumb");
		print "$_[0] --> $post/$base\n";
		return ("$post/$base-thumb.$FinalImageExt", $FullSizeURL);
	}
}

# read source pdf and trim edges
sub ReadPDF {
	my $PDF = Image::Magick->new;
	$PDF->Set(density=>$PdfDensity);
	$PDF->Set(units=>"PixelsPerInch");
	my $x = $PDF->Read("$_[0]");
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

sub GetBaseExt() {
	my $file = $_[0];
	my @dot = split(/\./, $file);
	my $ext = pop(@dot);
	my $base = join('', @dot);
	return ($base, $ext);
}