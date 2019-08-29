#!/bin/bash

export PATH="$PATH:/c/github/otc-vsts-agent"

#source <(otc-task --download-only $OTC_TASK_VERSION_PATH_SEGMENT shared.sh)

source <(otc-task-include shared.sh)

hello-function

echo "Hello World!"
echo $1 
echo $2
echo $3
