todo

- include youtube video links as embeds in the sidebar
- don't include old shit at all? include a selection?
- fix upper case filename issues?

done

- fix bug: triplicating
- fix bug: post-pages aren't being generated unless i do all of them
- youtube embeds as .youtube files
- next and previous month on month archive pages
- handle post deletion
- put the yearlist at the bottom of each post page too
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