cd C:\Users\you\zcom-perl
perl zpublish.pl %1 %2 > zpublishbat.log
perl zcompile.pl >> zpublishbat.log
git commit -m "automatic publish commit"