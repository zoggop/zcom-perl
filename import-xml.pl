use XML::Feed;
use LWP::UserAgent;
use LWP::Simple;
use URI::Escape;
use Text::Markdown;

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

my @iPre = (
	'a',
	'img'
);
my @iMid = (
	'href',
	'src'
);
# my $imagePre = '<a href="';
# my $imagePost = '</a>';
my $captionPre = '<td class="tr-caption"';
my $captionPost = '</td>';

# storage
my $untitled = 0;

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
		# get images and clean them from html
		$body = GetImages($body, $shortname);
		my $md = reverseMarkdown($body);
		# write the outcome
		my $year = $dt->year();
		my $month = $dt->month_name();
		my $day = $dt->day();
		my $hour = $dt->hour();
		my $min = $dt->min();
		print $title, ' -> ', $shortname, " $day $month $year $hour:$min\n";
		open (FILE, ">import/$shortname.md");
		binmode(FILE, ":utf8");
		print FILE "# $title\n";
		print FILE "## $day $month $year $hour:$min\n\n";
		print FILE $md;
		close(FILE);
	}
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

sub GetImages() {
	my $html = $_[0];
	my $shortname = $_[1];
	my $captionout;
	my $cleaned = $html;
	my $t = 0;
	foreach my $ip (@iPre) {
		my $imagePre = '<' . $ip;
		my $imageMid = $iMid[$t] . '="';
		my $imagePost = '</' . $ip . '>';
		if ($html =~ m/\Q$imagePre/) {
			my @images = split(/\Q$imagePre/, $html, -1);
			my $nothing = shift(@images);
			my $i = 1;
			foreach my $thing (@images) {
				# $thing is everything from the beginning of one tag to the beginning of the next (useful for finding captions)
				(my $tag, $nothing) = split(/\Q$imagePost/, $thing); # $tag is only the tag we're interested in
				($nothing, my $url) = split(/\Q$imageMid/, $tag);
				($url, $nothing) = split(/"/, $url);
				my @dot = split(/\./, $url);
				my $ext = uc($dot[$#dot]);
				# print $ext, "\n";
				if ($imageExts{$ext}) {
					# clean tag
					my $erase = $imagePre . $tag . $imagePost;
					$cleaned =~ s/\Q$erase/ /g;
					# get image filename
					my @slash = split(/\//, $url);
					my $filename = $slash[$#slash];
					$filename = sprintf("%02d", $i) . '-' . $filename;
					# get image if necessary
					unless (-d "import/$shortname") { mkdir "import/$shortname"; }
					unless (-e "import/$shortname/$filename") {
						my $data = get($url);
						unless (defined $data) {print "WARNING: COULD NOT GET $url\n"; }
						open(FILE, ">import/$shortname/$filename");
						binmode(FILE);
						print FILE $data;
						close(FILE);
						print "$filename written\n";
					} else {
						print "$filename already exists\n";
					}
					# deal with caption if present
					if ($thing =~ m/\Q$captionPre/) {
						($nothing, my $capthing) = split(/\Q$captionPre/, $thing);
						($capthing, $nothing) = split(/\Q$captionPost/, $capthing);
						($nothing, my $caption) = split(/>/, $capthing, 2);
						$caption = reverseMarkdown($caption);
						$caption =~ s/\n/ /g;
						$captionout = $captionout . $filename . "\n" . $caption . "\n";
						my $erasecap = $captionPre . $capthing . $captionPost;
						$cleaned =~ s/\Q$erasecap/ /g;
					}
					$i = $i + 1;
				}
				$html = $cleaned;
			}
			$t = $t + 1;
		}
	}
	# write captions file
	if ($captionout) {
		open(FILE, ">import/$shortname/assets.captions");
		print FILE $captionout;
		close(FILE);
		print "assets.captions written\n";
	}
	return $cleaned;
}

sub reverseMarkdown() {
	my $req = HTTP::Request->new(POST => 'http://heckyesmarkdown.com/go/');
	$req->content_type('application/x-www-form-urlencoded');
	$req->content('html=' . uri_escape_utf8($_[0]));
	# send request
	$res = $ua->request($req);
	if ($res->is_success) {
		return $res->decoded_content;
	} else {
		print "Error: " . $res->status_line . "\n";
		return;
	}
}

# &lt;a href="http://3.bp.blogspot.com/-3Q9n7FRCDrM/USvNrkW8_yI/AAAAAAAAEx0/L_cJVTM5P7Y/s1600/0224131549.jpg" imageanchor="1" &gt;&lt;img border="0" src="http://3.bp.blogspot.com/-3Q9n7FRCDrM/USvNrkW8_yI/AAAAAAAAEx0/L_cJVTM5P7Y/s320/0224131549.jpg" /&gt;&lt;/a&gt;&lt;p&gt;

# <a href="http://4.bp.blogspot.com/-lh7IdsJ_TxY/USvNxZG-RTI/AAAAAAAAEx8/yP6l7PguPBs/s1600/0224131556.jpg" imageanchor="1" ><img border="0" src="http://4.bp.blogspot.com/-lh7IdsJ_TxY/USvNxZG-RTI/AAAAAAAAEx8/yP6l7PguPBs/s320/0224131556.jpg" /></a>

# <a href="http://3.bp.blogspot.com/-3Q9n7FRCDrM/USvNrkW8_yI/AAAAAAAAEx0/L_cJVTM5P7Y/s1600/0224131549.jpg" imageanchor="1" ><img border="0" src="http://3.bp.blogspot.com/-3Q9n7FRCDrM/USvNrkW8_yI/AAAAAAAAEx0/L_cJVTM5P7Y/s320/0224131549.jpg" /></a