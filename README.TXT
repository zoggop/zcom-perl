todo

- handling of post file changes (right now it renames the post file because it thinks it's a duplicate, not an update)
- create zpublish.pl
	- grabs any markdown file with a # Title on the first line, adds the file's date to the second line, copies it to posts/ and runs zcompile.pl
- create a context menu that uses zpublish.pl
- create a writemonkey plugin that uses zpublish.pl