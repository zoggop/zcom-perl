#!/bin/bash
perl zpublish.pl $1 $2 > znowpublishsh.log
perl zcompile.pl >> znowpublishsh.log
bash gitupdate.sh