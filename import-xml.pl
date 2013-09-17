use XML::Feed;
use LWP::UserAgent;
use LWP::Simple;
use URI::Escape;

my $ua = LWP::UserAgent->new;

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

my $imagePre = ']: http';
my $imagePost = '\n';

my $feed = XML::Feed->parse($ARGV[0])
    or die XML::Feed->errstr;
print $feed->title, "\n";
for my $entry ($feed->entries) {
	if ($entry->category =~ m/kind\#post/) {
		my $dt = $entry->issued;
		my $title = $entry->title;
		my $shortname = TitleToShortName($title);
		my $content = $entry->content;
		my $body = $content->body;
		my $url = 'http://heckyesmarkdown.com/go/';
		my $req = HTTP::Request->new(POST => $url);
		$req->content_type('application/x-www-form-urlencoded');
  		$req->content('html=' . uri_escape_utf8($body));
		# send request
		$res = $ua->request($req);
		# write the outcome
		my $year = $dt->year();
		my $month = $dt->month_name();
		my $day = $dt->day();
		print $title, ' -> ', $shortname, " $day $month $year\n";
		open (FILE, ">import/$shortname.md");
		binmode(FILE, ":utf8");
		print FILE "# $title\n";
		print FILE "## $day $month $year\n\n";
		if ($res->is_success) {
			my $md = $res->decoded_content;
			$md = GetImages($md, $shortname);
			print FILE $md;
		}
		else { print "Error: " . $res->status_line . "\n"; }
	}
}

sub TitleToShortName() {
	my $shortname= lc($_[0]);
	$shortname =~ s/[^a-z0-9]/_/g;
	return $shortname;
}

sub GetImages() {
	my $md = $_[0];
	my $shortname = $_[1];
	if ($md =~ m/$imagePre/) {
		# my @images = split(/\[[0-9]\]: http/, $md);
		my @images = split(/$imagePre/, $md);
		my $cleaned = $md;
		for ($i=2; $i<=$#images; $i=$i+1) {
			my $image = $images[$i];
			my $nothing;
			(my $url, $nothing) = split(/$imagePost/, $image);
			my @dot = split(/\./, $url);
			my $ext = uc($dot[$#dot]);
			print $ext, "\n";
			if ($imageExts{$ext}) {
				# clean text of image reference
				my $before = substr $images[$i-1], -2, 2;
				my $eraseref = $before . $imagePre . $url;
				print $eraseref, "\n";
				$cleaned =~ s/$eraseref//;
				# grab image
				$url = 'http' . $url;
				print $url, "\n";
				my $data = get($url);
				die "Couldn't get it!" unless defined $data;
				# write image
				my @slash = split(/\//, $url);
				my $filename = $slash[$#slash];
				mkdir "import/$shortname";
				open(FILE, ">import/$shortname/$filename");
				binmode(FILE);
				print FILE $data;
				close(FILE);
				print "$filename written\n";
				# clean out image tag
				my $eraseimg = '![' . $filename . ']' . $before . ']';
				print $eraseimg, "\n";
				$cleaned =~ s/$eraseimg//; 
			}
		}
		print $cleaned;
		return $cleaned;
	} else {
		return $md;
	}
}