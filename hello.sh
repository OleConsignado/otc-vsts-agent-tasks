#!/bin/bash

export PATH="$PATH:/c/github/otc-vsts-agent"

otc-task master shared.sh

hello-function

echo "Hello World!"
echo $1 
echo $2
echo $3
