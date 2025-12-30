#!/bin/bash

if [ ! -f .env ]; then
 echo "ERROR - missing .env file!"
 exit 1
fi

# Load the token from .env
source .env
REPO=$(pwd |xargs basename)

URL="github.com/xoroz/$REPO.git"
# Configure git to use the token temporarily
git remote set-url origin "https://${GITHUB_TOKEN}@$URL"
git add *
git commit -m "Commit msg: $1"
# Push your changes
git push origin main
# Reset to original URL (security best practice)
git remote set-url origin "https://$URL"

