#!/bin/sh

# Abort on error
set -e

LANG=C
LC_CTYPE=C
OS=`uname`

SED="sed -i -E -e"
if [ "${OS}" = "Darwin" ]; then
  SED="sed -i '' -E -e"
fi

echo "Removing trailing whitespace"
find . -type f -not -path './.git/*' -name *.h -or -name *.java -or -name *.js -or -name *.m -exec ${SED} 's/[[:space:]]+$//g' {} \;

echo "Removing multiple blank lines"
find . -type f -not -path './.git/*' -name *.h -or -name *.java -or -name *.js -or -name *.m -exec ${SED} '/./,/^$/!d' {} \;

echo "Converting line endings"
find . -type f -not -path './.git/*' -name *.h -or -name *.java -or -name *.js -or -name *.m -exec dos2unix {} \; > /dev/null 2>&1
