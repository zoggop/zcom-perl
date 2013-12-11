#!/bin/bash
HOST='nwbiolog.com'
USER='zoggop@nwbiolog.com'
PASS='frumpl3'
TARGETFOLDER='/'
SOURCEFOLDER='/home/zoggop/win8/zcom-perl/build'
 
lftp -f "
open $HOST
user $USER $PASS
lcd $SOURCEFOLDER
mirror --reverse --delete --verbose --use-cache --no-perms $SOURCEFOLDER $TARGETFOLDER
bye
"