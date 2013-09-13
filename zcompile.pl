# zoggop dot com static website compiler

# config variables
my $frontPageDays = 7; # how many days beyond the first post to display on the front page

# read last checksums and dates to compare against
my %lastCheckSums {};
my %lastDates = {};
if (-e "posts.inventory") {
	open(FILE, "posts.inventory")
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
opendir(DIR, "posts")
@postfiles = <DIR>;
closedir(DIR)
my @newPosts;
foreach my $postfile (@postfiles) {
	my $checksum = md5_hex(do { local $/; IO::File->new($postfile)->getline });
	if ($checksum ne $lastCheckSums{$postfile}) {
		push(@newPosts, $postfile);
	}
}

# read new posts and create their post pages
my @pages = ();
my %pageRef = {};
my $ref = 0;
foreach my $postfile (@newPosts) {
	my $page = {};
	($page->{'Title'}, $page->{'Date'}, $page->{'Content'}) = ReadPost($postfile);
	$page->{'md'} = $postfile;
	$pages[$ref] = $page;
	$pageRef{$postfile} = $ref;
	BuildPostPage($postfile);
	$ref = $ref + 1;
}


#
# SUBROUTINES
#

# build a post page
sub BuildPostPage() {
	my $ref = $pageRef{$_[0]};
	my %page = %{ $pages[$ref] };
	foreach my $key (keys %page) { $buffer{$key} = $page{$key}; }
	
}

# read a post
sub ReadPost() {
	my $postfile = $_[0];
	if (-e $postfile) {

		return ($title, $date, $content);
	} else {
		return;
	}
}

# read last newest post
sub GetLastNewestPost() {
	if (-e "posts.newest") {
		open(FILE, "posts.newest")
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