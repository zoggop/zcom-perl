# zoggop dot com static website compiler

# read old checksums to check against
my @oldchecksums;
if (-e "posts.checksums") {
	open(FILE, "posts.checksums")
	@cslines = <FILE>;
	close(FILE)
}

# read post markdown checksums to find new posts
opendir(DIR, "posts")
@postfiles = <DIR>;
closedir(DIR)
foreach my $postfile (@postfiles) {
	my $checksum = md5_hex(do { local $/; IO::File->new("filename")->getline });

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