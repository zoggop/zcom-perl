todo

- put the yearlist at the bottom of each post page too
- handle post deletion
- don't include old shit at all? include a selection?
- "next month" or "next year" etc at bottom of index and archive pages, some way of transversing
- fix upper case filename issues?
- create a writemonkey plugin that uses zpublish.pl


done

- show a postlist on each post page as on the index, but just one post before and after
- check if asset directory has changed to register a new post
- hosted on github
- fix month archives
- ordering issues fixed ($daysold is only used to determine what shows up on the front page, everything else is datenumbers)
- create a context menu that uses zpublish.pl (made "send to")
- create zpublish.pl
	- grabs any markdown file with a # Title on the first line, adds the file's date to the second line, copies it to posts/ and runs zcompile.pl
- compile per-year and/or per-month archive pages
- a front page last-month headline list
- post asset handling (images, file links)